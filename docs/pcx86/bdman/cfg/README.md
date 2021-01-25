---
layout: sheet
title: Configuring BASIC-DOS
permalink: /docs/pcx86/bdman/cfg/
---

{% include header.html %}

### System Configuration

When BASIC-DOS starts, it automatically allocates enough memory for:

- Up to 20 open files at a time
- Up to 4 active sessions at a time

However, those limits, along with other default settings, can be changed
through entries in a special file named **CONFIG.SYS** on your BASIC-DOS
start-up diskette.

For example, if the following lines appear in **CONFIG.SYS**:

	FILES=30
	SESSIONS=8

then memory will be set aside for up to 30 simultaneous open files and up to
8 simultaneous active sessions.

{% include footer.html prev="Contents:../" next="" %}
