# 4d-plugin-raw-keydown

Captures raw key-down events and hands each one to a 4D method of your choice, even when no form field has focus. It was written for USB-HID barcode scanners, which behave like keyboards and "type" the barcode followed by Return or Tab. On macOS it installs a Carbon application event handler; on Windows it installs a low-level keyboard hook (`WH_KEYBOARD_LL`). Each key-down is queued and delivered, in order, to your callback method as a key code, a one-character `Text` and a process number, from a plugin-owned process named `$KEYDOWN`.

| Command | Returns | Purpose |
|---|---|---|
| [ON RAW KEYDOWN CALL](#on-raw-keydown-call) | — | Start or stop delivering raw key-down events to a method |

**Platforms:** macOS (Carbon event handler) and Windows 32/64-bit (low-level keyboard hook).

## Versioning and manual publication

**Bump version** is manual: select the branch in Actions and choose `patch`,
`minor`, or `major`. It checks out the immutable selected commit, requires a
clean checkout and an unchanged remote branch, validates the source metadata,
then commits only these files:

- `Keyboard Events.xcodeproj/project.pbxproj`
- `Info.plist`
- `English.lproj/InfoPlist.strings`

The existing workflow header promised coordinated marketing/current versions.
`MARKETING_VERSION` across the three project configurations and the source
plist establish the existing `1.0.2` authority. This migration repairs the stale
source `CURRENT_PROJECT_VERSION` (`1.0.0`) and localized strings (`1.0`) to that
authority, without incrementing the release version. Future bumps require strict
`X.Y.Z` agreement across both project keys and the localized version strings.
Supported Xcode references (`$(MARKETING_VERSION)` / `${MARKETING_VERSION}` and
their current-version counterparts where they resolve without a cycle) remain
references. Absent `CFBundleVersion` stays absent. Prebuilt bundles, 4D project
metadata, dependency versions, schema versions and localization counters are not
release-version inputs and are not rewritten.

The push is a non-force update to the explicitly selected branch, with both
`push.followTags=false` and `--no-follow-tags`. A mandatory executable pre-push
guard checks Git's advertised old SHA against the selected SHA, and checks the
new commit, direct parent and target ref. It rejects late advances, ancestor
rewinds, deletion and same-result races, including changes after the last
`ls-remote`. Missing or non-executable guards fail closed. A bump creates no tag
and does not start Build.

**Build** is a separate manual workflow with no inputs. Select the branch after
the bump; every checkout uses that run's `github.sha`, and the source metadata
determines the release version. Windows x64 is built first, then macOS
arm64/x86_64, with the Windows binary merged into the canonical bundle. Existing
artifact checks, universal-binary verification, Developer ID signing and
verification, ZIP/DMG notarization and DMG stapling remain mandatory.

Publication is serialized repository-wide across branches without cancelling a
running build. Before building and again immediately after all build/package/
signing/notarization gates, it checks remote tags and the authenticated,
paginated releases list, including drafts. API 404s, authentication/network
errors, malformed pages or entries and failures on later pages are errors, not
evidence of absence. Only a complete successful no-match permits creation.

Publication creates `vX.Y.Z` at the exact selected SHA through a create-only
Git refs POST and verifies the remote SHA. Even a concurrent same-SHA tag is a
conflict. It then creates a new public, non-prerelease release with that tag,
explicit SHA, tag-name title and an empty body (no generated notes), and uploads
`Keyboard Events-X.Y.Z.zip` and `Keyboard Events-X.Y.Z.dmg` separately to the
returned new release ID. Existing tags, drafts, releases and assets are never
updated, overwritten or deleted.

**Failure recovery:** the workflow stops without rollback or retry. A tag, a
release or earlier uploaded assets may remain after a later failure, including
an ambiguous API response. Inspect the retained state and logs manually; do not
rerun the same version expecting an overwrite or cleanup. Resolve the incident
under maintainer control, then use a new source version for a fresh publication.

This migration does not modernize the legacy native project or bypass signing
requirements. The Windows job retains its v143/Windows 10 overrides over the
project's legacy SDK/toolset settings; macOS retains Carbon, AppKit,
CoreGraphics, the vendored 4D Plugin API, universal architecture selection and
the existing deployment-target override. Hosted-runner compatibility and signing
credential availability remain separate operational concerns.

Local checks (no native build, signing, dispatch or publication):

```sh
python3 -m unittest discover -s .github/tests -v
actionlint .github/workflows/*.yml
```

The lifecycle suite uses live-derived source expectations, temporary source
copies and local bare Git remotes for race tests; it does not publish remotely.

---

## Requirements & platform notes

- There is exactly one command, and it takes three parameters. It has no return value and does not raise a 4D error if monitoring cannot start (see [Error handling](#error-handling--troubleshooting)).
- Monitoring is global to the plugin: there is one active listener, one method, one process number and one filter setting. Calling the command again replaces all three.
- Your callback does **not** run in the process that called the command. It runs in a plugin-created process named `$KEYDOWN`. Share data with your own process through an interprocess variable (as in the example below) and wake your process with `POST OUTSIDE CALL`.
- **On Windows**, the hook is system-wide. It sees keystrokes typed into any application, not only 4D, and with the default `filter` value of `0` it also consumes them (see the command description). **On macOS**, only events delivered to the 4D application are seen, so 4D must be the frontmost application.
- Only key-down events are captured. Key-up is ignored on both platforms. On Windows, auto-repeat key-downs from a held key are reported; Alt-modified keys (system key-downs) are not captured.
- Monitoring is stopped automatically when 4D quits, but it is **not** stopped when your process ends. Always stop it yourself (for example in `On Unload`).

---

## ON RAW KEYDOWN CALL

### Syntax

```4d
ON RAW KEYDOWN CALL ( method ; process ; filter )
```

| Parameter | Type | Description |
|---|---|---|
| `method` | Text | Name of the callback method. Pass an empty string to stop monitoring. |
| `process` | Longint | Process number passed through to the callback as its third parameter, normally `Current process`. |
| `filter` | Longint | `0`: key-downs are consumed (the application does not receive them). Non-zero: key-downs are also passed on to the application. |
| Result | — | The command returns nothing. |

### Description

**Starting.** Pass a method name to begin monitoring. The plugin looks the name up once, when you call the command. If the lookup succeeds, each key is delivered by calling the method directly. If it does not, the plugin falls back to running the name through `EXECUTE METHOD` on every key. In that case a mistyped name is only noticed when the first key arrives.

**Stopping.** Pass an empty string. The plugin removes the keyboard handler and waits (up to 5 seconds) for its `$KEYDOWN` process to exit. It is safe to stop from inside the callback itself. The README example passes only the method name when stopping; since the command is declared with three parameters, passing all three is the safe form.

**The callback.** Your method receives three parameters:

| Parameter | Type | Description |
|---|---|---|
| `$1` | Longint | Key code. **On macOS**, the hardware key code (a physical key position, independent of layout). **On Windows**, the virtual-key code (`VK_*`). The two numbering schemes are different. |
| `$2` | Text | One character for the key, or an empty/NUL character if the key has no character (see below). |
| `$3` | Longint | The `process` value you passed to the command. |

**Delivery.** Keys are queued while your method runs and delivered in order, one call per key. The queue holds up to 1024 keys; beyond that, further keys are dropped silently, for example if your method blocks for a long time.

**Character differences.**

- **On Windows**, `$2` comes from the virtual-key code alone and ignores Shift and the keyboard layout. Letters are always uppercase, shifted punctuation is not produced, and keys with no character (Shift, Ctrl, arrows, function keys) arrive with an empty or NUL `$2`. Pressing Shift for a capital letter produces its own call.
- **On macOS**, `$2` is the character code the system reports for the key, with modifiers applied (so `a` and `A` differ). Modifier keys alone do not generate key-down events. Only single-byte characters are supported; codes of `0x80` and above, such as accented characters on non-US layouts, may be empty or garbled.

If you need an exact scanner payload, treat these as limits: filter out empty/NUL characters in the callback, and do not rely on letter case on Windows.

**Filter.** With `filter = 0`, the plugin consumes each key-down, so typing in 4D fields does nothing while monitoring is active. **On Windows** this applies to every application on the machine. A non-zero `filter` passes the key on as well. The README refers to a constant `KE Filter keystroke` for this parameter; its value is not part of the plugin files, so check its value in your database's constants before relying on its meaning.

### Example

From the plugin's README (form method):

```4d
$event:=Form event

Case of 
: ($event=On Load)

ON RAW KEYDOWN CALL ("CB";Current process;KE Filter keystroke)

: ($event=On Unload)

ON RAW KEYDOWN CALL ("")

: ($event=On Outside Call)

variable:=<>KEY

<>KEY:=""

End case 
```

From the plugin's own callback method (`CB.4dm`):

```4d
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
```

The callback appends each character to `<>KEY` and, when a terminator (Return, line feed or Tab, how most scanners end a barcode) arrives, posts an outside call to the form's process. The form then reads and clears `<>KEY`.

Variation: ignore keys with no character, so Shift and similar keys do not pollute the buffer (useful on Windows):

```4d
C_LONGINT($1;$code)
C_TEXT($2;$char)
C_LONGINT($3;$info)
C_TEXT(<>KEY)

$code:=$1
$char:=$2
$info:=$3

Case of 
: (Length($char)=0)
  //no character for this key: ignore
: (Character code($char)=0)
  //NUL: ignore
: ($char="\r") | ($char="\n") | ($char="\t")
POST OUTSIDE CALL($info)
Else 
<>KEY:=<>KEY+$char
End case 
```

---

## Helper method: CB

**`CB ( $1 : Longint ; $2 : Text ; $3 : Longint )`**

This is example glue code shipped with the plugin, not part of its command set. Copy it into your database under any name and pass that name to `ON RAW KEYDOWN CALL`.

| Parameter | Type | Description |
|---|---|---|
| `$1` | Longint | Key code (platform-specific, see above) |
| `$2` | Text | Character for the key |
| `$3` | Longint | Process number to notify when a terminator key arrives |

See the full method in the example above. It declares the interprocess variable `<>KEY` and posts the outside call.

---

## Worked example: barcode input

Form method:

```4d
C_TEXT(<>KEY)
$event:=Form event

Case of 
: ($event=On Load)
<>KEY:=""
  //filter=0: scanner keystrokes are consumed and do not type into fields
ON RAW KEYDOWN CALL ("CB";Current process;0)

: ($event=On Outside Call)
$barcode:=<>KEY
<>KEY:=""
If (Length($barcode)>0)
  //look up $barcode here
End if 

: ($event=On Unload)
ON RAW KEYDOWN CALL ("";Current process;0)
End case 
```

Using a non-zero `filter` instead lets keystrokes continue to the application, so a barcode also types into whichever field has focus.

---

## Error handling & troubleshooting

- **Nothing happens and no error appears.** If the macOS handler or the Windows hook cannot be installed (for example a 4D Server running as a Windows service has no desktop session), the command returns without any indication. Check that the callback is firing, for example by logging in the callback.
- **Mistyped method name.** The plugin cannot resolve the name at call time and falls back to `EXECUTE METHOD` for every key. No error is raised by the command itself.
- **Keyboard appears dead.** With `filter = 0` all key-downs are consumed. On Windows this affects every application, so always stop monitoring in `On Unload` and test with a way to recover (a mouse).
- **Monitoring continues after your process ends.** The plugin does not tie monitoring to the process that started it. If your process is aborted before running `On Unload`, call `ON RAW KEYDOWN CALL("")` from another process, or quit 4D.
- **Windows: slow or lagging typing system-wide.** The hook runs on 4D's main thread. If 4D is busy for a long time, Windows may delay keystrokes everywhere and can silently remove the hook after a timeout, after which no events arrive.
- **Windows: capitals and punctuation are wrong, NUL characters appear.** See "Character differences". Ignore empty/NUL characters and do not depend on case.
- **Keys lost under load.** The queue holds 1024 keys; any further keys are dropped.
- **macOS: nothing captured.** Only events delivered to 4D are seen, so 4D must be frontmost.
- **Callback runs in `$KEYDOWN`, not your process.** Do not read your form's variables from the callback; use interprocess variables and `POST OUTSIDE CALL`.

---

## Quick reference

```4d
  //start
ON RAW KEYDOWN CALL ("CB";Current process;0)

  //callback: $1 code, $2 character, $3 process
POST OUTSIDE CALL($3)  //wake the form, On Outside Call

  //stop
ON RAW KEYDOWN CALL ("";Current process;0)
```
