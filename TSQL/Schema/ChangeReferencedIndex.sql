
--Adam Machanic's script does DROPs and CREATEs
--"To use the script, simply put SSMS into "results in text" mode, specify your target table, and hit F5, CTRL-E, or the 
--Play button. The result should be a nicely-formatted script containing all of the drops and creates, in the correct order. 
--(Foreign keys dropped first, then nonclustered indexes, then the clustered index, if appropriate. Creates are scripted in the 
--reverse order.)
--Note: Don't forget to configure the maximum text size in SSMS before using. The default is 256 characters--not enough for many cases. To configure, use the following sequence:
--Tools->Options->Query Results->Results to Text->Maximum number of characters->8192
-- "

Note that it looks like there is a check for SQL version that you might have to update/comment out
http://sqlblog.com/blogs/adam_machanic/archive/2010/04/04/rejuvinated-script-creates-and-drops-for-candidate-keys-and-referencing-foreign-keys.aspx

