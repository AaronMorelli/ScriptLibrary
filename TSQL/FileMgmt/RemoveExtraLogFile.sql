USE tempdb 
GO
--0. Make sure that no longer tranactions are running (e.g. a big report, or a purge process). They can hold
-- the tran log active for longer periods of time and make the below steps not work correctly.

--1. First, we tell tempdb to flush all its modified data to disk and clear all but the active portion
-- of the transaction log. 
CHECKPOINT;
GO

--2. Then, we find the logical name of the second LDF
--	copy the "name" column for the row you want to remove
SELECT * FROM sys.database_files WHERE [type]=1;
GO

--3. Prepare to remove the file. This has worked for me even when the "active" portion of
--	the log was in the new file
DBCC SHRINKFILE (templog2, EMPTYFILE);
GO

--4. The actual remove
ALTER DATABASE tempdb
REMOVE FILE templog2; 
GO

--5. Run this again to confirm there's only 1 row now
SELECT * FROM sys.database_files WHERE [type]=1;
GO

--5b. If the remove doesn't work and there are still 2 log files, run this
-- and look for where the "Status" field = 2, whether it is in the FileId
-- of the old log file or the temporary one
DBCC LOGINFO;
GO

--may come in handy, but not an explicit step right now.
--DBCC SQLPERF(LOGSPACE)

