//%attributes = {}
C_LONGINT:C283($1; $code)
C_TEXT:C284($2; $char)
C_LONGINT:C283($3; $info)

$code:=$1  //physical position 
$char:=$2  //ascii
$info:=$3  //$2 of ON RAW KEYDOWN CALL

C_TEXT:C284(<>KEY)

If ($char="\r") | ($char="\n") | ($char="\t")
	
	POST OUTSIDE CALL:C329($info)
	
Else 
	
	<>KEY:=<>KEY+$char
	
End if 