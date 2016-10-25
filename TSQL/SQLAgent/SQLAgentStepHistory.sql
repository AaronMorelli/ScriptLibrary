DECLARE @start DATETIME='2016-10-25 16:00',
		@end DATETIME='2016-10-25 17:00',
		@startdate_msdb INT,
		@starttime_msdb INT;
SET @startdate_msdb = CONVERT(INT,REPLACE(CONVERT(NVARCHAR(20),CONVERT(DATE,@start)),'-', ''));
SET @starttime_msdb = CONVERT(NVARCHAR(20),DATEPART(HOUR, @start)) + CONVERT(NVARCHAR(20),DATEPART(MINUTE, @start)) + CONVERT(NVARCHAR(20),DATEPART(SECOND, @start));

IF OBJECT_ID('tempdb..#JerbCompletions') IS NOT NULL
BEGIN
	DROP TABLE #JerbCompletions;
END
CREATE TABLE #JerbCompletions (
	job_id				UNIQUEIDENTIFIER NOT NULL,
	instance_id			BIGINT NOT NULL, 
	prev_instance_id	BIGINT NOT NULL
);
CREATE UNIQUE CLUSTERED INDEX CL1 ON #JerbCompletions(job_id, instance_id);

INSERT INTO #JerbCompletions (job_id, instance_id, prev_instance_id)
SELECT jh0.job_id, jh0.instance_id, ISNULL(PrevInstance.instance_id,-1)
FROM msdb.dbo.sysjobhistory jh0
	OUTER APPLY (
					SELECT TOP 1 jhprev.instance_id
					FROM msdb.dbo.sysjobhistory jhprev
					WHERE jhprev.job_id = jh0.job_id
					AND jhprev.step_id = 0
					AND jhprev.instance_id < jh0.instance_id
					ORDER BY jhprev.instance_id DESC
				) PrevInstance
WHERE jh0.step_id = 0
AND jh0.run_date >= @startdate_msdb
;

SELECT
	StartTime = REPLACE(CONVERT(NVARCHAR(40), StartTime, 102),'.', '-') + ' ' + CONVERT(NVARCHAR(40), StartTime, 108), 
	JobName, --JobInstanceID, StepInstanceID, 
	Step = step_id, StepName = step_name, 
	
	[Dur(sec)] = run_duration,
	EndTime = CASE WHEN DATEDIFF(DAY, StartTime, DATEADD(SECOND, run_duration, StartTime)) <> 0
					THEN REPLACE(CONVERT(NVARCHAR(40), DATEADD(SECOND, run_duration, StartTime), 102),'.', '-') + 
							' ' + CONVERT(NVARCHAR(40), DATEADD(SECOND, run_duration, StartTime), 108)
					ELSE CONVERT(NVARCHAR(20),CONVERT(TIME(0),DATEADD(SECOND, run_duration, StartTime)))
					END,
	[Status] = CASE WHEN run_status = 1 THEN N'Success'
					WHEN run_status = 0 THEN N'Failed'
					WHEN run_status = 2 THEN N'Retry'
					WHEN run_status = 3 THEN N'Cancelled'
					WHEN run_status = 4 THEN N'Running'
					ELSE CONVERT(NVARCHAR(10), run_status) END,
	[Retries] = retries_attempted,
	StepError = CASE WHEN sql_message_id = 0 AND sql_severity = 0 THEN N'' 
				ELSE N'Msg:' + CONVERT(NVARCHAR(20),sql_message_id) + N', Sev:' + CONVERT(NVARCHAR(20),sql_severity) + N' ' + StepError
				END,
	NextAction = CASE WHEN run_status = 1
					THEN (CASE WHEN step_id = 0 THEN N''
								WHEN on_success_action = 1 THEN N'Quit w/success'
								WHEN on_success_action = 2 THEN N'Quit w/failure'
								WHEN on_success_action = 3 THEN N'Next step'
								WHEN on_success_action = 4 THEN N'Go to step#' + CONVERT(NVARCHAR(20),on_success_step_id)
								ELSE CONVERT(NVARCHAR(20),on_success_action)
								END)
					ELSE (CASE WHEN step_id = 0 THEN N''
								WHEN on_fail_action = 1 THEN N'Quit w/success'
								WHEN on_fail_action = 2 THEN N'Quit w/failure'
								WHEN on_fail_action = 3 THEN N'Next Step'
								WHEN on_fail_action = 4 THEN N'Go to step#' + CONVERT(NVARCHAR(20),on_success_step_id)
								ELSE CONVERT(NVARCHAR(20),on_fail_action)
								END)
					END,
	--sql_message_id, sql_severity, run_status, 
	Notify, Subsys = ISNULL(subsystem,N''), DBName = ISNULL(database_name,N''),
	CmdText = CASE WHEN step_id = 0 THEN N''
				ELSE (SELECT [processing-instruction(q)]= ss.command
                            FOR XML PATH(''),TYPE)
				END,
	StepMessage,
	OutputFileLoc = ISNULL(output_file_name,N''),
	[TableLog(maybe)] = CASE WHEN ISNULL(flags,0) = 0 THEN N''
				ELSE (
					SELECT 
						--sjsl.log
						(SELECT [processing-instruction(q)]= ( N'[Date_Created: ' + CONVERT(VARCHAR(20), date_created) + N']' + NCHAR(10)+
																N'[Date_Modified: ' + CONVERT(VARCHAR(20), date_modified) + N']' + NCHAR(10)+
						 										sjsl.log
															)
                            FOR XML PATH(''),TYPE
						)
					FROM msdb.dbo.sysjobstepslogs sjsl
					WHERE sjsl.step_uid = ss.step_uid
					AND DATEDIFF(MINUTE, 
							DATEADD(SECOND, run_duration, StartTime), 
							sjsl.date_modified
							) < 15		--sure... if the log is w/in 15 min of job end, we'll consider that "close enough"
					)
				END
FROM (
	SELECT JobName = --We show the job name only for "completion" rows, except if there is no completion row found
					-- for this job instance
					CASE WHEN h.step_id = 0 OR jc.prev_instance_id < 0 THEN j.name
						ELSE N'' END, 
		JobInstanceID = jc.instance_id,
		StepInstanceID = h.instance_id, h.step_id, 
		h.step_name, h.sql_message_id, h.sql_severity, h.run_status, h.retries_attempted,
		StartTime = msdb.dbo.agent_datetime(h.run_date, h.run_time), 
		StepMessageXML.StepMessage,
		StepError = CASE WHEN h.sql_message_id = 0 THEN N''		--pass thru construct is prob fastest b/c we expect errors to be infrequent
						ELSE (SELECT ISNULL(m.text,N'<null>')
								FROM sys.messages m
								WHERE h.sql_message_id = m.message_id
								AND h.sql_severity = m.severity
								AND m.language_id = 1033)
						END,
		Notify = CASE WHEN operator_id_emailed = 1 THEN N'email ' ELSE N'' END + 
				CASE WHEN operator_id_netsent = 1 THEN N'netsent ' ELSE N'' END + 
				CASE WHEN operator_id_paged = 1 THEN N'paged ' ELSE N'' END,
		sjs.subsystem, sjs.database_name,sjs.retry_interval,
		sjs.command,
		sjs.on_success_action, 
		sjs.on_success_step_id,sjs.on_fail_action,sjs.on_fail_step_id,h.job_id, 
		sjs.output_file_name, sjs.flags, sjs.step_uid,

		--ugh, parse out run_duration
		--h.run_duration,
		run_duration = ((h.run_duration/1000000)*86400) + 
			(((h.run_duration-((h.run_duration/1000000)*1000000))/10000)*3600) + 
			(((h.run_duration-((h.run_duration/10000)*10000))/100)*60) + (h.run_duration-(h.run_duration/100)*100)
	FROM msdb.dbo.sysjobhistory h
		LEFT OUTER JOIN #JerbCompletions jc
			ON h.job_id = jc.job_id
			AND h.instance_id > jc.prev_instance_id
			AND h.instance_id <= jc.instance_id
		INNER JOIN msdb.dbo.sysjobs j
			ON h.job_id = j.job_id
		LEFT OUTER JOIN msdb.dbo.sysjobsteps sjs		--LOJ b/c step_id 0 has no match of course
			ON h.job_id = sjs.job_id
			AND h.step_id = sjs.step_id
		OUTER APPLY (SELECT StepMessage=(SELECT [processing-instruction(q)]=h.message
                            FOR XML PATH(''),TYPE)) StepMessageXML
	WHERE h.run_date >= @startdate_msdb
	AND h.run_time >= @starttime_msdb
) ss
WHERE StartTime BETWEEN @start AND @end
--and JobName <> N'job to omit'
ORDER BY JobInstanceID,step_id
OPTION(RECOMPILE);
