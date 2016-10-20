# 
Get-ChildItem C:\ -Recurse | Sort Length -desc | Select-Object -First 25
# adding GridView causes a pop-up UI that allows further filtering criteria
Get-ChildItem D:\ -Recurse | Sort Length -desc | Select-Object -First 25 |Out-GridView


