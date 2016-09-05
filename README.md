# 4d-plugin-raw-keydown
Directly capture raw keydown events on Mac; written for USB-HID barcode scanner input

##Platform

| carbon | cocoa | win32 | win64 |
|:------:|:-----:|:---------:|:---------:|
|🆗|🆗|🚫|🚫|

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

$1:=$code  //physical position 
$2:=$char  //ascii
$3:=$userInfo  //$2 of ON RAW KEYDOWN CALL

C_TEXT(<>KEY)

If ($code=48) | ($code=36) | ($code=76)  //tab, return, enter

CALL PROCESS($info)

Else 

<>KEY:=<>KEY+$char

End if 
```
