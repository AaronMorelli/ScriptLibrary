--TODO: create a "fast way" (using DMVs, but not guaranteed to be accurate) and a "accurate way" (running SELECT COUNT(*))
USE <dbname>
GO
SET NOCOUNT ON;
IF OBJECT_ID('tempdb..#objs') IS NOT NULL
BEGIN
	DROP TABLE #objs;
END

CREATE TABLE #objs (
	ObjectName VARCHAR(256) NOT NULL
);

IF OBJECT_ID('tempdb..#objs2') IS NOT NULL
BEGIN
	DROP TABLE #objs2;
END

CREATE TABLE #objs2 (
	ObjectName VARCHAR(256) NOT NULL,
	RowCnt BIGINT NOT NULL
);

INSERT INTO #objs (ObjectName)
SELECT quotename(SCHEMA_NAME(o.schema_id)) + '.' + quotename(o.name)
FROM sys.objects o
WHERE o.type = 'U'
AND o.name not like '%staging%'
and o.name not like '%scrubbing%'
and o.name not like '%2016%'
;

DECLARE iterateObjs CURSOR FOR 
SELECT ObjectName 
FROM #objs
ORDER BY ObjectName;

DECLARE @DynSQL VARCHAR(MAX),
	@curObjName VARCHAR(256);

OPEN iterateObjs;
FETCH iterateObjs INTO @curObjName;

WHILE @@FETCH_STATUS = 0
BEGIN
	SET @DynSQL = '
	INSERT INTO #objs2 (ObjectName, RowCnt)
	SELECT ''' + @curObjName + ''', ss.rc
	FROM (SELECT COUNT(*) as rc FROM ' + @curObjName + ' WITH (NOLOCK)) ss;'

	raiserror(@DynSQL, 10, 1) WITH NOWAIT;
	exec (@dynsql);

	FETCH iterateObjs INTO @curObjName;
END

CLOSE iterateObjs;
DEALLOCATE iterateObjs;

SELECT * 
FROM #objs2
ORDER BY ObjectName ASC;

