USE master 
GO
SET NOCOUNT ON;
GO
DECLARE @RunCommands INT,
		@PrintDebug INT,
		@DynSQL NVARCHAR(4000),
		@curDBName NVARCHAR(128),
		@curFixCmd NVARCHAR(1000)
		;
SET @RunCommands = 1;
SET @PrintDebug = 1;

IF OBJECT_ID('tempdb..#ConstraintFixes_Total') IS NOT NULL
BEGIN
	DROP TABLE #ConstraintFixes_Total;
END

IF OBJECT_ID('tempdb..#ConstraintFixes_CurrentIteration') IS NOT NULL
BEGIN
	DROP TABLE #ConstraintFixes_CurrentIteration;
END

CREATE TABLE #ConstraintFixes_Total (
	ConstraintType NVARCHAR(20),
	FixCmd NVARCHAR(4000),
	DBName NVARCHAR(128),
	SchemaName NVARCHAR(128),
	ObjectName NVARCHAR(128),
	ObjectType NVARCHAR(10),
	FKName NVARCHAR(128),
	IsNotForReplication INT,
	IsDisabled INT,
	ObjSize_pages BIGINT
);

CREATE TABLE #ConstraintFixes_CurrentIteration (
	ConstraintType NVARCHAR(20),
	FixCmd NVARCHAR(4000),
	DBName NVARCHAR(128),
	SchemaName NVARCHAR(128),
	ObjectName NVARCHAR(128),
	ObjectType NVARCHAR(10),
	FKName NVARCHAR(128),
	IsNotForReplication INT,
	IsDisabled INT,
	ObjSize_pages BIGINT
);

DECLARE iterateDBs CURSOR LOCAL STATIC FORWARD_ONLY FOR
SELECT DB_NAME(database_id)
FROM sys.databases d
WHERE d.name NOT IN (N'tempdb', N'master', N'model', N'msdb')
and d.name not in ('')		--exclusions here
--debug:
--and d.name = N'database name'
AND d.state_desc = 'ONLINE'
ORDER BY d.name
;

OPEN iterateDBs;
FETCH iterateDBs INTO @curDBName;

WHILE @@FETCH_STATUS = 0
BEGIN
	IF @PrintDebug = 1
		PRINT N'Evaluating database ' + ISNULL(@curDBName,N'<null>');
	
	TRUNCATE TABLE #ConstraintFixes_CurrentIteration;

	SET @DynSQL = N'USE ' + QUOTENAME(@curDBName) + N';
INSERT INTO #ConstraintFixes_CurrentIteration 
	(ConstraintType, FixCmd, DBName, SchemaName,ObjectName,ObjectType,
	FKName,IsNotForReplication,ObjSize_pages)
SELECT ''ForeignKey'', 
  FixCmd = ''ALTER TABLE '' + QUOTENAME(s.name) + ''.'' + QUOTENAME(o.name) + '' WITH CHECK CHECK CONSTRAINT '' + QUOTENAME(f.name) + '';'',
  DB_NAME(),
  SchemaName = s.name,
  ObjectName = o.name,
  ObjectType = o.type,
  FKName = f.name,
  IsNotForReplication = f.is_not_for_replication,
  ObjSize
FROM sys.objects o 
  INNER JOIN sys.schemas s 
    ON o.schema_id = s.schema_id
  INNER JOIN sys.foreign_keys f
    ON f.parent_object_id = o.object_id
  OUTER APPLY (
	  --sum across partitions, but just for base table
	  -- should be able to ignore LOB size b/c no FKs on lobs
    SELECT 
      [ObjSize] = ISNULL(ps.in_row_reserved_page_count,0) + ISNULL(ps.row_overflow_reserved_page_count,0)
    FROM sys.dm_db_partition_stats ps
    WHERE ps.object_id = o.object_id
    AND ps.index_id IN (0,1)
  ) ObjSz
WHERE f.is_not_trusted = 1;
';

	EXEC (@DynSQL);

		SET @DynSQL = N'USE ' + QUOTENAME(@curDBName) + N';
INSERT INTO #ConstraintFixes_CurrentIteration 
	(ConstraintType, FixCmd, DBName, SchemaName,ObjectName,ObjectType,
	FKName,IsNotForReplication,IsDisabled,ObjSize_pages)
SELECT ''CheckConstraint'',
  FixCmd = ''ALTER TABLE '' + QUOTENAME(s.name) + ''.'' + QUOTENAME(o.name) + '' WITH CHECK CHECK CONSTRAINT '' + QUOTENAME(c.name) + '';'',
  DB_NAME(),
  SchemaName = s.name,
  ObjectName = o.name,
  ObjectType = o.type,
  CCName = c.name,
  IsNotForReplication = c.is_not_for_replication,
  IsDisabled = c.is_disabled,
  ObjSize
from sys.objects o
  INNER JOIN sys.schemas s 
    ON o.schema_id = s.schema_id
  INNER JOIN sys.check_constraints c
    ON c.parent_object_id = o.object_id
  OUTER APPLY (
	  --sum across partitions, but just for base table
	  -- should be able to ignore LOB size b/c no FKs on lobs
    SELECT 
      [ObjSize] = ISNULL(ps.in_row_reserved_page_count,0) + ISNULL(ps.row_overflow_reserved_page_count,0)
    FROM sys.dm_db_partition_stats ps
    WHERE ps.object_id = o.object_id
    AND ps.index_id IN (0,1)
  ) ObjSz
WHERE c.is_not_trusted = 1;
';

	EXEC (@DynSQL);

	IF EXISTS (SELECT * FROM #ConstraintFixes_CurrentIteration)
	BEGIN

		INSERT INTO #ConstraintFixes_Total
		SELECT * FROM #ConstraintFixes_CurrentIteration;

		DECLARE iterateCmds CURSOR LOCAL STATIC FORWARD_ONLY FOR
		SELECT FixCmd
		FROM #ConstraintFixes_CurrentIteration
		;

		OPEN iterateCmds;
		FETCH iterateCmds INTO @curFixCmd;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @curFixCmd = N'USE ' + QUOTENAME(@curDBName) + N';' + @curFixCmd;

			IF @PrintDebug = 1
			BEGIN
				PRINT @curFixCmd;
			END

			IF @RunCommands = 1
			BEGIN
				EXEC(@curFixCmd);
			END

			FETCH iterateCmds INTO @curFixCmd;
		END

		CLOSE iterateCmds;
		DEALLOCATE iterateCmds;
	END		--IF EXISTS (SELECT * FROM #ConstraintFixes_CurrentIteration)

	FETCH iterateDBs INTO @curDBName;
END

CLOSE iterateDBs;
DEALLOCATE iterateDBs;

SELECT * FROM #ConstraintFixes_Total
ORDER BY DBName, ConstraintType, FixCmd
;
