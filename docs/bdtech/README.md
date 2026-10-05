---
layout: sheet
manual: BASIC-DOS Technical Reference
title: Contents
permalink: /docs/bdtech/
---

{% include header.html %}

The BASIC-DOS Technical Reference describes BASIC-DOS's internal architecture and programming interfaces, for programmers writing software that runs on BASIC-DOS or working on BASIC-DOS itself.  For information on using BASIC-DOS, see the [BASIC-DOS Manual](../bdman/).

1. [Architecture](arch/)
	- [Components](arch/#components)
	- [Boot Process](arch/#boot-process)
	- [Memory Layout](arch/#memory-layout)
	- [Sessions](arch/#sessions)
	- [Interrupt Vectors](arch/#interrupt-vectors)
2. [DOS Functions](dos/) (INT 21h)
	- [Function Summary](dos/#function-summary)
	- [Differences from PC DOS](dos/#differences-from-pc-dos)
	- [Error Codes](dos/#error-codes)
3. [Utility Functions](util/) (INT 32h)
4. [Device Drivers](dev/)
	- [Driver Headers](dev/#driver-headers)
	- [Request Packets](dev/#request-packets)
	- [IOCTL Functions](dev/#ioctl-functions)
	- [Built-in Drivers](dev/#built-in-drivers)
5. [Floating-Point Interface](fpu/) (FPU$)
6. [Data Structures](data/)

The definitions referred to throughout are found in the BASIC-DOS source code, primarily in these include files (in `software/pcx86/src/os/inc`):

- **dosapi.inc**: DOS and utility function numbers, and the PSP, EPB, SPB, FFB, and FCB structures
- **devapi.inc**: device driver headers, attributes, and IOCTL codes
- **dev.inc**: device driver commands, packets, and error codes
- **dos.inc**: internal structures (SCB, MCB, SFB, and the register frame)
- **fpu.inc**: the FPU$ function table

**NOTE**: BASIC-DOS is a work-in-progress, and these interfaces may change.

{% include footer.html prev="Cover:/docs/" next="Architecture:arch/" %}
