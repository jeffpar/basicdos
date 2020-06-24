WH_Ed122.ZIP includes

        README.TXT      1997-12-14      This file.
        WH_wEdit.EXE    1997-12-14      A Windows help file editor, v. 1.22.
	HISTORY.TXT	1997-12-14	Program history list.
        FILE_ID.DIZ     1997-12-14      Identification file.

Windows help files can have their initial window position and size defined
at compile time - secondary windows in help files even must have these
properties defined. The position and size are defined as fractions of the
display screen, and therefore it can give inconveniences to carry help files
between different graphics platforms.

The WH_wEdit program can edit Windows help files compiled with the HC31 or
HCP help file compilers. WH_wEdit will let you edit both the windows' size and
position, and the background colors of the header and text sections of the
windows. Help files compiled with the HC30 compiler cannot be edited as the
HC30 compiler does not support a [WINDOWS] section in the Help Project File.

WH_wEdit also facilitates macro editing. Windows help file macros perform
initialization when the file is loaded by WinHelp. For example, if browsing
is enabled (i.e. if << and >> pushbuttons are available) the help file will
include the macro
	BrowseButtons()
which instructs WinHelp to show the pushbuttons on the button bar. Macro
editing is a delicate matter, and you should not use the macro editor unless
you know what you are doing. You will get the same warning every time you
enable the editor after you have loaded WH_wEdit. For professional help file
authors only: If you start WH_wEdit with four positive integers as parameters,
the macro editor window is opened unconditionally without any warning, with
position and size defined by the four integers (20 320 550 250 is fine for
800x600+). Only professional help file authors should use this option.

Version 1.12+ of WH_wEdit accepts Windows 95 type help files. It can also open
all observed kinds of .MVB (Mulitmedia Viewer Book) files, however, it cannot
edit the windows properties of MVB type 27 files. It will let you know if you
open such file.

The program recognizes four types of help files:
	15	Windows 3.0 files (no windows to edit)
	21	Windows 3.1 files and .MVB files
	27	.MVB files (position/size/colors cannot be edited)
	33	Windows 95 files

The size of a help file is defined in the file's header. If the physical file
is longer than this size, WH_wEdit will offer to truncate the file. WH_wEdit
cannot edit the file unless it is truncated. A 72 bytes appendix has been
observed to files compiled with RoboHelp. No problems have been observed
truncating such help files. However, truncation is irreversible, so be sure
to have a copy of your help file before you let WH_wEdit truncate it.

WH_wEdit is a Windows application program. It is straightforward to use and
has these few lines of online help:
	Select a Help file from the "File" menu
	Select a window to edit from the "Windows" list
	Check appropriate "Defined" checkboxes to enable editing
	Click on the "Change" pushbutton to facilitate editing
	Select the "Edit" menu to enable macros editing
The "WH_wEdit Sample" position and size editor window and the "Color" editor
window have separate online help. The Macros Editor operates almost identical
to Windows' NotePad editor. It includes copy and paste, so that you can copy
macros from one help file - or other sources - to the clipboard, and paste
them into other help files.

A few hints are appropriate, though. File|Save will save the current state of
a file unconditionally. File|Open and File|Exit will notify the user about
changes selectively to the Windows part and in the Macros editor, and a save
can be accepted or refused individually; selecting Cancel in any of these two
windows will return you to the current state of the editor. If any changes
were refused, and opening of a file was then canceled in the Open dialog box,
then the changes will remain in the editor, but they are marked as saved.

Text can be entered in the Macros editor even if no file is open; WH_wEdit
will offer to copy the editor's contents to the clipboard if you attempt to
save this text or to open a file.

The program can report the following errors:

Cannot open <name>				Not found, or readonly
<name> has unknown format			Probably not a help file
<name> was compiled with HC30, can't edit	No windows to edit
Insufficient heap for windows in <name>		More local memory needed
No windows were defined in <name>	     *)	Compiled without definitions
Cannot reopen <name> for update			Another application deleted
Length of <name> has changed, can't update	  or changed the help file
Nothing to save					Attempt to save unedited file
Window clipped at screen edge			Parts of sample off screen
<name> has MVB type 27 windows. WH_wEdit cannot
  edit position, size and colors of these
  windows.				     *)	Format not supported
Known/Unknown appendix <n> bytes long. Truncate
  after help file?				Truncate in order to edit
*) These are not error messages if the Macros Editor is enabled, then the
   macros can be edited.

There are 16 more possible errors concerning the help file format. I would
appreciate to be informed if an error message appear not listed above, or if
the "Insufficient heap" message appears.

WH_wEdit is copyright (C) 1994-1997 Bent Lynggaard. The program is freeware,
thus it can be used without any registering. It may be distributed from
Bulletin Board Services.

The program may not be included in any commercial software package or
shareware package without my permission. It may be included in public domain
and freeware software packages provided that:
     1. It is included in the original WH_Ed122.ZIP package together with this
        README file, and with my PKZIP authenticity code intact (KJO555).
     2. It is included in the package for a specific help file editing purpose.
I would appreciate to be notified if WH_wEdit is included in a public domain
package.

WH_wEdit is supplied without any warranties.

Make backups of your help files before you edit them.

1997-12-14.
Bent Lynggaard <bent.lynggaard@risoe.dk> on Internet.
