use <dbname>
go

SELECT 
  FixCmd = 'ALTER TABLE ' + QUOTENAME(s.name) + '.' + QUOTENAME(o.name) + ' WITH CHECK CHECK CONSTRAINT ' + QUOTENAME(f.name),
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
GO

SELECT 
  FixCmd = 'ALTER TABLE ' + QUOTENAME(s.name) + '.' + QUOTENAME(o.name) + ' WITH CHECK CHECK CONSTRAINT ' + QUOTENAME(c.name),
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
GO
