$event:=Form event code:C388

Case of 
	: ($event=On Load:K2:1)
		
		ON RAW KEYDOWN CALL("CB"; Current process:C322; KE Filter keystroke)
		
	: ($event=On Unload:K2:2)
		
		ON RAW KEYDOWN CALL("")
		
	: ($event=On Outside Call:K2:11)
		
		variable:=<>KEY
		
		<>KEY:=""
		
End case 