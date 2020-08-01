#
# BASIC-DOS Makefile
#
# @author Jeff Parsons <Jeff@pcjs.org>
# @copyright © 2012-2020 Jeff Parsons
# @license MIT <https://www.pcjs.org/LICENSE.txt>
#
# This file is part of PCjs, a computer emulation software project at pcjs.org
#
ASM=MASM
LINK=LINK
AFLAGS=/D$(REL)
MAPSYM=MAPSYM

#
# Inference rules in the DOS MAKE utility apparently work only if the
# files are in the same folder.  So for now, these rules must be copied
# under each dependency.
#
.ASM.OBJ:
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GWDATA.OBJ: ..\GWDATA.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GWMAIN.OBJ: ..\GWMAIN.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

OEM.OBJ: ..\OEM.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GWEVAL.OBJ: ..\GWEVAL.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GWLIST.OBJ: ..\GWLIST.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

IBMRES.OBJ: ..\IBMRES.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

BIMISC.OBJ: ..\BIMISC.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

DSKCOM.OBJ: ..\DSKCOM.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

BIPTRG.OBJ: ..\BIPTRG.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

BIPRTU.OBJ: ..\BIPRTU.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

BISTRS.OBJ: ..\BISTRS.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

FIVEO.OBJ: ..\FIVEO.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GENGRP.OBJ: ..\GENGRP.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

ADVGRP.OBJ: ..\ADVGRP.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

MACLNG.OBJ: ..\MACLNG.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GWSTS.OBJ: ..\GWSTS.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GIO86.OBJ: ..\GIO86.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GIODSK.OBJ: ..\GIODSK.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GIOKYB.OBJ: ..\GIOKYB.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GIOSCN.OBJ: ..\GIOSCN.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GIOLPT.OBJ: ..\GIOLPT.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GIOCOM.OBJ: ..\GIOCOM.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GIOCON.OBJ: ..\GIOCON.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GIOTBL.OBJ: ..\GIOTBL.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

SCNEDT.OBJ: ..\SCNEDT.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

SCNDRV.OBJ: ..\SCNDRV.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

CALL86.OBJ: ..\CALL86.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

NEXT86.OBJ: ..\NEXT86.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

MATH.OBJ: ..\MATH.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

KANJ86.OBJ: ..\KANJ86.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GIOCAS.OBJ: ..\GIOCAS.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

ITSA86.OBJ: ..\ITSA86.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GWRAM.OBJ: ..\GWRAM.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GWINIT.OBJ: ..\GWINIT.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

BIBOOT.OBJ: ..\BIBOOT.ASM
	$(ASM) $(AFLAGS) /I.. $**,$@,$*.LST;

GWB.EXE: GWDATA.OBJ GWMAIN.OBJ OEM.OBJ GWEVAL.OBJ GWLIST.OBJ IBMRES.OBJ \
	BIMISC.OBJ DSKCOM.OBJ BIPTRG.OBJ BIPRTU.OBJ BISTRS.OBJ FIVEO.OBJ \
	GENGRP.OBJ ADVGRP.OBJ MACLNG.OBJ GWSTS.OBJ GIO86.OBJ GIODSK.OBJ \
	GIOKYB.OBJ GIOSCN.OBJ GIOLPT.OBJ GIOCOM.OBJ GIOCON.OBJ GIOTBL.OBJ \
	SCNEDT.OBJ SCNDRV.OBJ CALL86.OBJ NEXT86.OBJ MATH.OBJ KANJ86.OBJ \
	GIOCAS.OBJ ITSA86.OBJ GWRAM.OBJ GWINIT.OBJ BIBOOT.OBJ
	$(LINK) /MAP @$*.LRF
	$(MAPSYM) $*

