/*  File usage percent breakdown query */
USE <dbname>
GO
IF OBJECT_ID('TempDB..#showfilestats1') IS NOT NULL
BEGIN
 DROP TABLE #showfilestats1 
END

CREATE TABLE #showfilestats1 (FileID INT, [FileGroup] INT, TotalExtents BIGINT, UsedExtents BIGINT, lname varchar(512), pname varchar(512))
INSERT INTO #showfilestats1 (FileID, [FileGroup], TotalExtents, UsedExtents, lname, pname)
 EXEC ('DBCC showfilestats')

SELECT ss.FileGroup, FileGroupName, ss.Physical_Name as FilePathName, ss.Logical_Name as FileLogicalName, ss.FileID, 
 ss.FileSize_GB, ss.UsedSize_GB,  [FreeSpace_GB] = ss.filesize_GB - ss.UsedSize_GB,
 [FilePctFull] = CONVERT(varchar(20),CONVERT(decimal(15,1),100*(ss.UsedSize_GB/ss.FileSize_GB)))+'%' ,
 ss.TotalDBSize_GB, ss.TotalUsedSize_GB,
 [PctOfTotalFileSize] = convert(varchar(20),convert(decimal(15,1),(100*ss.FileSize_GB / ss.TotalDBSize_GB))) + '%',
 [PctOfTotalUsedSize] = convert(varchar(20),convert(decimal(15,1),(100*ss.UsedSize_GB / ss.TotalUsedSize_GB))) + '%'
FROM (SELECT t.FileGroup, dsp.name as FileGroupName ,
 [Physical_Name]=t.pname, 
 [Logical_Name] = t.lname, 
 t.FileID, 
 [FileSize_GB] = CONVERT(DECIMAL(15,1),CONVERT(DECIMAL(15,3),t.TotalExtents)*64./1024./1024.),
 [UsedSize_GB] = CONVERT(DECIMAL(15,1),CONVERT(DECIMAL(15,3),t.UsedExtents)*64./1024./1024.), 
 [TotalDBSize_GB] = CONVERT(DECIMAL(15,1),CONVERT(DECIMAL(15,3),(SUM(TotalExtents) OVER ()))*64./1024./1024.),
 [TotalUsedSize_GB] = CONVERT(DECIMAL(15,1),CONVERT(DECIMAL(15,3),(SUM(UsedExtents) OVER ()))*64./1024./1024.)
FROM #showfilestats1 t 
 inner join sys.data_spaces dsp
  on dsp.data_space_id = t.FileGroup
) ss
ORDER BY FileGroup ASC




/*  Indexes by File Group */
use ReportingDW
go
SELECT FileGroupName, SchemaName, TableName, IndexName, index_id, Rsvd_MB
from (SELECT dsp.name as FileGroupName,  SCHEMA_NAME(o.schema_id) as SchemaName,
 o.name as TableName,  i.name as IndexName, 
 i.index_id, (ps.reserved_page_count*8/1024) as Rsvd_MB
FROM sys.objects o
 INNER JOIN sys.indexes i  ON o.object_id = i.object_id
 INNER JOIN sys.data_spaces dsp  ON i.data_space_id = dsp.data_space_id
 INNER JOIN sys.dm_db_partition_stats ps  ON i.object_id = ps.object_id
  AND i.index_id = ps.index_id
WHERE o.type = 'U'  and (ps.reserved_page_count*8/1024) > 400 --only indexes > 400 MB
) ss
WHERE 1=1
--AND ss.tablename in ('mytablesgohere')
--order by 6 desc
ORDER BY Rsvd_MB DESC 




