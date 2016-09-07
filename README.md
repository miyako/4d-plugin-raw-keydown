# 4d-plugin-raw-keydown
Directly capture raw keydown events; written for USB-HID barcode scanner input

##Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
|🆗|🆗|🆗|🆗|

##Example

```
$event:=Form event

Case of 
: ($event=On Load)

ON RAW KEYDOWN CALL ("CB";Current process)

: ($event=On Unload)

ON RAW KEYDOWN CALL ("")

: ($event=On Outside Call)

variable:=<>KEY

<>KEY:=""

End case 
```

* Callback Code

```
C_LONGINT($1;$code)
C_TEXT($2;$char)
C_LONGINT($3;$info)

$code:=$1  //physical position 
$char:=$2  //ascii
$info:=$3  //$2 of ON RAW KEYDOWN CALL

C_TEXT(<>KEY)

If ($char="\r") | ($char="\n") | ($char="\t")

CALL PROCESS($info)

Else 

<>KEY:=<>KEY+$char

End if 
```
