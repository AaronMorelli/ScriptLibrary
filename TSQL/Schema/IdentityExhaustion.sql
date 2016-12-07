SELECT
	TableName, 
	ColumnName, 
	ColumnType, 
	LastIDVal = SUBSTRING(LastIDVal, 1, CHARINDEX('.', LastIDVal)-1),
	MaxVal, 
	PctDepleted
FROM (
	SELECT 
		TableName, 
		ColumnName,
		ColumnType,
		LastIDVal = CONVERT(varchar(20),CONVERT(money,LastIdentity),1),
		MaxVal = MaxValue_Display,
		PctDepleted = CASE WHEN MaxValue = -1 THEN N'?'
						ELSE CONVERT(varchar(20),
									CONVERT(DECIMAL(35,2),100.*(CONVERT(DECIMAL(35,4),LastIdentity) / CONVERT(DECIMAL(35,4),MaxValue))))
						END,
		PCTDepleted_Num = CASE WHEN MaxValue = -1 THEN -1
						ELSE 100.*(CONVERT(DECIMAL(35,4),LastIdentity) / CONVERT(DECIMAL(35,4),MaxValue))
						END
	FROM (
		SELECT TableName = quotename(s.name + '.' + o.name),
			LastIdentity = ident_current(s.name + '.' + o.name), 
			ColumnName = c.name, 
			ColumnType = t.name, 
			MaxValue = CASE WHEN t.name = 'int' THEN 2147483647
							WHEN t.name = 'bigint' THEN 9223372036854775807
							WHEN t.name = 'smallint' THEN 32767
							WHEN t.name = 'tinyint' THEN 255
						ELSE -1
						END,
			MaxValue_Display = CASE WHEN t.name = 'int' THEN N'2,147,483,647'
							WHEN t.name = 'bigint' THEN N'9,223,372,036,854,775,807'
							WHEN t.name = 'smallint' THEN N'32,767'
							WHEN t.name = 'tinyint' THEN N'255'
						ELSE N'-1'
						END
		FROM sys.columns c 
			INNER JOIN sys.objects o
				ON c.object_id = o.object_id
			INNER JOIN sys.schemas s
				ON o.schema_id = s.schema_id
			INNER JOIN sys.types t
				ON t.system_type_id = c.system_type_id
				AND t.user_type_id = c.user_type_id
		WHERE c.is_identity = 1
		AND o.type = 'U'
	) ss
) ss2
WHERE PCTDepleted_Num > 25.0
ORDER BY PCTDepleted_Num DESC;
