/* Originally pulled from this Kendra Little blog post: https://www.littlekendra.com/2009/04/19/a-table-summarizing-all-agent-jobs-with-steps/
	Accessed on October 25, 2016.

	Modified in the following ways: 
		2016-10-25		Restructured to use OUTER APPLY instead of PIVOT so I could use XML
*/
use msdb;
set nocount on;
declare
    @query nvarchar(max)
    , @selectsql nvarchar(max)
	, @dynselectsql nvarchar(max)
	, @dynfromsql nvarchar(max)
    , @pivotsql nvarchar(max)
    , @showfullcommands bit=1
	, @curstepid INT
	;
IF OBJECT_ID('tempdb..#DistinctJobStepIDs') IS NOT NULL
BEGIN
	DROP TABLE #DistinctJobStepIDs;
END
CREATE TABLE #DistinctJobStepIDs (StepID INT NOT NULL);
INSERT INTO #DistinctJobStepIDs (StepID) SELECT DISTINCT step_id FROM msdb.dbo.sysjobsteps WHERE step_id IS NOT NULL;

SET @dynselectsql = N'';
SET @dynfromsql = N'';

DECLARE loopStepIDs CURSOR LOCAL FAST_FORWARD FOR
SELECT StepID 
FROM #DistinctJobStepIDs
ORDER BY StepID;

OPEN loopStepIDs;
FETCH loopStepIDs INTO @curstepid;

WHILE @@FETCH_STATUS = 0
BEGIN
	SET @dynselectsql = @dynselectsql + N'
		, Step' + cast(@curstepid as nvarchar) + N'= Step' + cast(@curstepid as nvarchar)+ N'.CmdText';

	SET @dynfromsql = @dynfromsql + N'
	OUTER APPLY (
		SELECT Step' + cast(@curstepid as nvarchar) + N' = 
			case sjs.subsystem
			  when ''CmdExec'' then ''CmdExec''
			  when ''SSIS'' then ''SSIS''
			  when ''TSQL'' then  sjs.database_name
			  else ''?''
			  end + '': ''
			 + sjs.step_name ' + 
				case @showfullcommands
					when 1 then '+'' = '' + char(10) + sjs.command '
					else ''
				end + N' 

		FROM msdb.dbo.sysjobsteps sjs ' + 
				case @showfullcommands 
					when 1 then N'
			OUTER APPLY (SELECT CmdText=(SELECT [processing-instruction(q)]=sjs.command
                            FOR XML PATH(''''),TYPE)) XMLConvert
					'
					else N''
				end + N'
		WHERE sjs.job_id = p.job_id
		AND sjs.step_id = ' + cast(@curstepid as nvarchar) + N'
	) Step'  + cast(@curstepid as nvarchar) + N'_base ' + 
		case @showfullcommands 
			when 1 then N'
	OUTER APPLY (SELECT CmdText=(SELECT [processing-instruction(q)]=Step' + cast(@curstepid as nvarchar) + N'_base.Step' + cast(@curstepid as nvarchar) + N'
				FOR XML PATH(''''),TYPE)) Step' + cast(@curstepid as nvarchar)
			else N''
		end
	
	;

	FETCH loopStepIDs INTO @curstepid;
END

CLOSE loopStepIDs;
DEALLOCATE loopStepIDs;

select @query='
select
    [Job Name]
    , [Enabled]
    , [Category Name]
    , [Desc]
    , [Last Run]
    , [Last Outcome]
    , Created
    , [Last Mod] '
+ @dynselectsql + '
from (
    select
        jb.job_id
        , [Job Name]=jb.name
        , jb.enabled
        , [Category Name]=sc.name
        , [Desc] = case jb.description
            when ''No description available.''
                then ''''
            else jb.description
            end
        , created=convert(char(8), jb.date_created, 1)
        , [Last Mod]=convert(char(8),jb.date_modified,1)
        , [Last Run]= convert (char(8),
                (select max(cast(cast(run_date as nvarchar)as datetime))
                from msdb.dbo.sysjobhistory jh  with (nolock)
                where jh.job_id=jb.job_id
                and step_id=0)
                , 1)
        , [Last Outcome]=
                (select case run_status
                    when 0 then ''Failed''
                    when 1 then ''Success''
                    when 2 then ''Retry''
                    when 3 then ''Canceled''
                    when 4 then ''In progress''
                    else cast(run_status as nvarchar)
                    end
              from msdb.dbo.sysjobhistory jh with (nolock)
              where jh.job_id=jb.job_id
              and instance_id =
                  (select max(instance_id)
                  from msdb.dbo.sysjobhistory jh2  with (nolock)
                  where jh2.job_id=jh.job_id
                  and jh2.step_id=0)
              )
  from msdb.dbo.sysjobs jb with (nolock)
  left join msdb.dbo.syscategories sc with (nolock) on
      jb.category_id=sc.category_id
) p
' + @dynfromsql;

--print @query
EXEC sp_executesql @query;
