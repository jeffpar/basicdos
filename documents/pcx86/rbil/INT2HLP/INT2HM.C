/********************************
 **              			   	 **
 **  INT2HM.C     			    **
 **  (INT list TO HelpMake)    **
 **              			       **
 **  by Giorgio Caimi		    **
 **              			       **
 ********************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

 /* Formats definition */

char intlist[]=
".context h.title\nINTERRUPTS,PORTS,MEMORY and CMOS Help\n"
".context h.default\n.topic INTERRUPTS LIST (copyrights)\n\n\n\n"
"               \\bINT2HM (INTerrupts list TO HelpMake converter)\\p\n"
"                 \\bby GIORGIO CAIMI (caimi@zeus.csr.unibo.it)\\p\n\n\n"
"       All documentation files except INTERRUPTS LIST, PORTS LIST and\n"
"       CATEGORY LIST  are  copied  into  the  data-base  as  they are\n"
"       provided.  Copyrights  and other restrictions applied from the\n"
"       authors are contained into those files.\n\n"
"       Copyrights for INTERRUPTS LIST,  PORTS LIST  and CATEGORY LIST\n"
"       belong  to the  respective authors;  copyright information had\n"
"       to be  removed  from the  original files  due to  the indexing\n"
"       process requirements.\n\n\n"
"                                                                 "
"\\u[\\u\\aOK\\vh.contents\\v\\u]\\u\n"
".context h.contents\n.topic FILES INDEX\n"
"    \\u[\\u\\aINTERRUPTS\\vis\\v\\u]\\u"
"  \\u[\\u\\aFAR CALLS\\vft\\v\\u]\\u"
"  \\u[\\u\\aMEMORY\\vmt\\v\\u]\\u"
"  \\u[\\u\\aPORTS\\vpi\\v\\u]\\u"
"  \\u[\\u\\aCMOS\\vct\\v\\u]\\u"
"          \\u[\\u\\aBACK\\v!B\\v\\u]\\u\n"
"  ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ\n\n"
" ÛÛÛÛ ÛÛ   ÛÛ ÛÛÛÛÛÛ ÛÛÛÛÛÛÛ ÛÛÛÛÛÛ  ÛÛÛÛÛÛ  ÛÛ  ÛÛ ÛÛÛÛÛÛ  ÛÛÛÛÛÛ  ÛÛÛÛ \n"
"  ÛÛ  ÛÛÛ  ÛÛ Û ÛÛ Û  ÛÛ   Û  ÛÛ  ÛÛ  ÛÛ  ÛÛ ÛÛ  ÛÛ  ÛÛ  ÛÛ Û ÛÛ Û ÛÛ  ÛÛ\n"
"  ÛÛ  ÛÛÛÛ ÛÛ   ÛÛ    ÛÛ Û    ÛÛ  ÛÛ  ÛÛ  ÛÛ ÛÛ  ÛÛ  ÛÛ  ÛÛ   ÛÛ   ÛÛÛ\n"
"  ÛÛ  ÛÛ ÛÛÛÛ   ÛÛ    ÛÛÛÛ    ÛÛÛÛÛ   ÛÛÛÛÛ  ÛÛ  ÛÛ  ÛÛÛÛÛ    ÛÛ    ÛÛÛ\n"
"  ÛÛ  ÛÛ  ÛÛÛ   ÛÛ    ÛÛ Û    ÛÛ ÛÛ   ÛÛ ÛÛ  ÛÛ  ÛÛ  ÛÛ       ÛÛ      ÛÛÛ\n"
"  ÛÛ  ÛÛ   ÛÛ   ÛÛ    ÛÛ   Û  ÛÛ  ÛÛ  ÛÛ  ÛÛ ÛÛ  ÛÛ  ÛÛ       ÛÛ   ÛÛ  ÛÛ\n"
" ÛÛÛÛ ÛÛ   ÛÛ  ÛÛÛÛ  ÛÛÛÛÛÛÛ ÛÛÛ  ÛÛ ÛÛÛ  ÛÛ ÛÛÛÛÛÛ ÛÛÛÛ     ÛÛÛÛ   ÛÛÛÛ\n\n"

"                       ÛÛÛÛ    ÛÛÛÛ  ÛÛÛÛ  ÛÛÛÛÛÛ\n"
"                        ÛÛ      ÛÛ  ÛÛ  ÛÛ Û ÛÛ Û\n"
"                        ÛÛ      ÛÛ  ÛÛÛ      ÛÛ\n"
"                        ÛÛ      ÛÛ   ÛÛÛ     ÛÛ\n"
"                        ÛÛ   Û  ÛÛ     ÛÛÛ   ÛÛ\n"
"                        ÛÛ  ÛÛ  ÛÛ  ÛÛ  ÛÛ   ÛÛ\n"
"                       ÛÛÛÛÛÛÛ ÛÛÛÛ  ÛÛÛÛ   ÛÛÛÛ\n\n"
"  ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ\n"
"                                   HelpMake converter by Giorgio Caimi\n",
fcall[]=".context ft\n.topic FARCALL.LST\n",
mem[]=".context mt\n.topic MEMORY.LST\n",
cmos[]=".context ct\n.topic CMOS.LST\n",
gloss[]=".context gt\n.topic GLOSSARY.LST\n",
keys[]=".context kt\n.topic CATEGORY.KEY\n",
klink[]="  \\u\\aSEARCHING KEYS\\vkt\\v\\u\n\n",
port[]=".context pi\n",
port_a[]=".context pt####\n",
port_b[]=".topic PORTS.LST\n",
intlst[]=".context is\n",
intlst_a[]=".context ii####\n",
intlst_b[]=".context it####\n",
intlst_c[]=".topic INTERRUP.LST\n",
intlst_d[]="\\bCATEGORY :\\p ##\n\\bKEY      :\\p #"
"                                                  ", /* filler[50] */
line[]=
"  ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ\n",
menu[]=
".freeze 2\n"
"    \\u[\\u\\aBACK\\v!B\\v\\u]\\u"
"  \\u[\\u\\aFILES INDEX\\vh.contents\\v\\u]\\u"
"                                 "
"  \\u[\\u\\aGLOSSARY\\vgt\\v\\u]\\u\n",
menuglo[]=
".freeze 2\n"
"    \\u[\\u\\aBACK\\v!B\\v\\u]\\u"
"  \\u[\\u\\aFILES INDEX\\vh.contents\\v\\u]\\u\n",
menuglo1[]=
".freeze 2\n"
"    \\u[\\u\\aFILES INDEX\\vh.contents\\v\\u]\\u"
"                                         "
"  \\u[\\u\\aGLOSSARY\\vgt\\v\\u]\\u\n",
menubas[]=
".freeze 2\n"
"    \\u[\\u\\aFILES INDEX\\vh.contents\\v\\u]\\u\n";

char *checkslash(char *str)
/* converts backslash into double-backslash */
{
	int i,h;

	for (i=0;str[i];i++) {
		if (str[i]=='\\') {
			for (h=strlen(str)+1;h>i;h--) str[h]=str[h-1];
			++i;
		}
	}
	return str;
}

void main(void)
{
	FILE *fs,*fd,*fi;
	char str[150],str1[150],str2[150],str3[10],str4[10],*error,hmfname[13];
	unsigned cnt,cnt1;
	int i,j,k,comp,intno,destno=0,ctxcont=0;

	printf("\n INT-list to HelpMake converter\n"
				" (c) 1994-95 by Giorgio Caimi\n\n"
            "Checking archives...");
  	if ((fopen("PORTS.LST","rb")==NULL)||
       (fopen("CMOS.LST","rb")==NULL)||
       (fopen("FARCALL.LST","rb")==NULL)||
		 (fopen("MEMORY.LST","rb")==NULL)||
		 (fopen("GLOSSARY.LST","rb")==NULL)||
		 (fopen("CATEGORY.KEY","rb")==NULL)) {
      fcloseall();
		printf("NEED 'PORTS.LST','MEMORY.LST','CMOS.LST',\n"
				 "                         "
				 "'GLOSSARY.LST','CATEGORY.KEY' AND 'FARCALL.LST'\n");
		putchar(7);
      exit(1);
   }
   fcloseall();

	if (fopen("INTERRUP.LST","rb")==NULL) {
   	fcloseall();
		printf("RUN 'COMBINE.BAT' FIRST\n");
		putchar(7);
      exit(2);
	}
	fcloseall();

	printf("OK\nWriting banner...");

   sprintf(hmfname,"INTLST%02X.HM",++destno);
	fd=fopen(hmfname,"wt");
	fputs(intlist,fd);

   printf("OK\nAdding 'FARCALL.LST'...");
	fs=fopen("FARCALL.LST","rt");
	fputs(fcall,fd); /* put context */
	fputs(menuglo1,fd); /* put menu */
   fputs(line,fd);
	while (fgets(str,95,fs)) fputs(checkslash(str),fd);
	fclose(fs);

  	printf("OK\nAdding 'MEMORY.LST'...");
   fs=fopen("MEMORY.LST","rt");
   fputs(mem,fd); /* put context */
	fputs(menuglo1,fd); /* put menu */
   fputs(line,fd);
	while (fgets(str,95,fs)) fputs(checkslash(str),fd);
	fclose(fs);

	printf("OK\nAdding 'CMOS.LST'...");
	fs=fopen("CMOS.LST","rt");
	fputs(cmos,fd); /* put context */
	fputs(menuglo1,fd); /* put menu */
   fputs(line,fd);
	while (fgets(str,95,fs)) fputs(checkslash(str),fd);
	fclose(fs);

	printf("OK\nAdding 'GLOSSARY.LST'...");
	fs=fopen("GLOSSARY.LST","rt");
	fputs(gloss,fd); /* put context */
	fputs(menuglo,fd); /* put menu */
   fputs(line,fd);
	while (fgets(str,95,fs)) fputs(checkslash(str),fd);
	fclose(fs);

   printf("OK\nConverting 'PORTS.LST'...");
	fs=fopen("PORTS.LST","rt");
	fi=fopen("PORTS.IDX","wt");
	cnt=0;str2[0]='\0';
   do {
   	while (strncmp(str2,"--------",8)) fgets(str2,95,fs);
      comp=strncmp(str2,"--------!---CONTACT",19);
      if (comp)
			if (str2[10]=='P') { /* found topic */
         	fgets(str2,95,fs);

			   strcpy(str,str2);
            str2[0]='\0';  /* topic formatting */
            i=j=0;
            if (!strncmp(str,"PORT",4)) i=5; /* some have "PORT", some not */
            while (str[i]&&(str[i]!=' ')&&(str[i]!='\t')) {
               str2[j]=str[i];
               ++i;++j;
            } /* reach end of port(s) number(s) */
            for (;j<10;j++) str2[j]=' '; /* align to column 10 */
            str2[j++]='-';
            while ((str[i]=='-')||(str[i]==' ')||(str[i]=='\t')) ++i; /* skip useless chars */
            str2[j++]=' ';
            for (;str[i];i++) { /* copy remaining chars */
               str2[j]=str[i];
               if (str2[j]=='\t') str2[j]=' ';
               ++j;
            }
            str2[j]='\0';
            checkslash(str2);

            fputs(str2,fi);   /* add entry to index */
			   fgets(str,95,fs);
			   while (!strcmp(str,"\n")) fgets(str,95,fs); /* search text */
			   if (strncmp(str,"--------",8)) {  /* Is there any description? */
				   sprintf(str1,"%04u\n",cnt++);
				   strncpy(port_a+11,str1,4);
               fputs(port_a,fd);fputs(port_b,fd);/* put context */
				   fputs(menu,fd);fputs(line,fd); /* put menu */
				   fputs("\\b",fd); /* bold on */
				   str2[strlen(str2)-1]='\0';fputs(str2,fd);
				   fputs("\\p\n\n",fd); /* bold off */
				   do
						fputs(checkslash(str),fd);
					while (fgets(str,95,fs),strncmp(str,"--------",8));
				   fputs(str1,fi);
				   ++ctxcont;
			   } else fputs("\n",fi);
            strcpy(str2,str);
	      } else fgets(str2,95,fs);
	} while (comp);
	fclose(fi);fclose(fs);

	printf("OK\nIndexing 'PORTS.LST'...");
	fs=fopen("PORTS.IDX","rt");
   fputs(port,fd);fputs(port_b,fd);
	fputs(menubas,fd);fputs(line,fd);
	while (fgets(str,95,fs)) {
		fgets(str1,95,fs);
		if ((k=strcmp(str1,"\n"))!=0) fputs("\\u\\a",fd);
      str[strlen(str)-1]='\0';  /* del newline */
		fputs(str,fd);
      if (k) {
			fputs("\\v",fd);
			strncpy(port_a+11,str1,4);
			strcpy(str1,port_a+9);
			str1[strlen(str1)-1]='\0';
			fputs(str1,fd);
			fputs("\\v\\u",fd);
			++ctxcont;
      }
      putc('\n',fd);
	}
   fclose(fs);
   unlink("PORTS.IDX");

	printf("OK\nConverting 'CATEGORY.KEY'...");
	fs=fopen("CATEGORY.KEY","rt");
	fputs(keys,fd); /* put context */
	fputs(menuglo,fd); /* put menu */
   fputs(line,fd);
	while (*fgets(str,95,fs)!='-') ;
   while (fgets(str,95,fs)) {
      error=str;
      while ((*error=='\t')||(*error==' ')) ++error;
      fputs(checkslash(error),fd);
   }
	fclose(fs);

	printf("OK\nConverting 'INTERRUP.LST'...");
	fs=fopen("INTERRUP.LST","rt");
	fi=fopen("INTERRUP.IDX","wt");
	cnt=cnt1=str[0]=0;intno=-1;
	do {
		do {
			strcpy(str2,str);
      	while (strncmp(str2,"--------",8))
				fgets(str2,95,fs);
			comp=strncmp(str2,"--------!---Admin",17);
			if ((comp)&&(str2[8]=='!')) fgets(str,95,fs);
		} while ((comp)&&(str2[8]=='!'));
		if (comp) {
 			intlst_d[15]=str2[8]; /* category (main) */
			i=10;j=33;
			for (;str2[i];i++) {  /* key */
				intlst_d[j]=str2[i];
				if (intlst_d[j]!='-') ++j;
			}
			intlst_d[j]='\0';
			str[0]=str2[10];str[1]=str2[11]; /* int no. */
			str[2]='\0';
			k=(int)strtol(str,&error,16);
			if ((k!=intno)||(cnt1==500)) {
            if (intno>=0) fputs("\n\n",fi);
            fputs(str,fi);  /* put int no. */
				putc('\n',fi);
				intno=k;cnt1=0;
			} else ++cnt1;
			fgets(str2,95,fs);
			intlst_d[16]=str2[7]; /* category (flag) */
			if (str2[7]=='-') i=9; else i=11;
			strcpy(str,str2+i); /* description */
			checkslash(str);
			sprintf(str1,"%04u\n",cnt++);
         fputs(str,fi);fputs(str1,fi);
			strncpy(intlst_b+11,str1,5);
			fputs(intlst_b,fd);fputs(intlst_c,fd);/* put context */
			fputs(menu,fd);fputs(line,fd); /* put menu */
			fputs("\\b",fd); /* bold on */
			str[strlen(str)-1]='\0';fputs(str,fd);
			fputs("\\p\n",fd); /* bold off */
			fputs(intlst_d,fd);
			putc('\n',fd);
			while (fgets(str2,95,fs),strncmp(str2,"--------",8))
				fputs(checkslash(str2),fd);
			strcpy(str,str2);
			++ctxcont;
			if (ctxcont==600) {
				ctxcont=0;
            sprintf(hmfname,"INTLST%02X.HM",++destno);
				freopen(hmfname,"wt",fd);
			}
		}
	} while (comp);
   fputs("\n\n",fi);
	fclose(fi);fclose(fs);

	printf("OK\nIndexing 'INTERRUP.LST'...");
	fs=fopen("INTERRUP.IDX","rt");
	fi=fopen("INTERRUP.CNT","wb");
	fputs(intlst,fd);fputs(intlst_c,fd); /* put context */
   fputs(menubas,fd);fputs(line,fd); /* put menu */
   fputs(klink,fd); /* put searching keys link */
   cnt=0;
   while (fgets(str,95,fs)) {
		str3[0]=str1[0]=cnt1=0;
		do {
			strcpy(str4,str3);
         fgets(str1,95,fs);
			fgets(str3,9,fs);
			++cnt1;
		} while (*str1!='\n');
		fputs("  \\u\\aINT ",fd);
 		str[strlen(str)-1]='\0';  /* del newline */
		fputs(str,fd);
		fputs("\\v",fd);
		if (cnt1==2) { /* put text */
			strncpy(intlst_b+11,str4,5);
			strcpy(str1,intlst_b+9);
		} else { /* put index */
			sprintf(str4,"%04u",cnt++);
			strncpy(intlst_a+11,str4,4);
			strcpy(str1,intlst_a+9);
		}
      str1[strlen(str1)-1]='\0';
		fputs(str1,fd);
		putw(cnt1-1,fi);
		fputs("\\v\\u\n",fd);
	}
	fclose(fs);fclose(fi);

   fs=fopen("INTERRUP.IDX","rt");
	fi=fopen("INTERRUP.CNT","rb");
	cnt=0;
	while ((k=getw(fi))!=EOF) {
		fgets(str,95,fs);
		if (k>1) {
			sprintf(str3,"%04u",cnt++);
			strncpy(intlst_a+11,str3,4);
 			fputs(intlst_a,fd);fputs(intlst_c,fd); /* put context */
			fputs(menu,fd);fputs(line,fd); /* put menu */
		}
		for (i=0;i<k;i++) {
			fgets(str,95,fs);
         fgets(str3,9,fs);
			if (k>1) {
				fputs("\\u\\a",fd);
				str[strlen(str)-1]='\0';  /* del newline */
				fputs(str,fd);
				fputs("\\v",fd);
				strncpy(intlst_b+11,str3,5);
				strcpy(str1,intlst_b+9);
				str1[strlen(str1)-1]='\0';  /* del newline */
				fputs(str1,fd);
            fputs("\\v\\u\n",fd);
			}
		}
      fgets(str3,9,fs);
		fgets(str3,9,fs);
	}

	fclose(fs);fclose(fi);
	unlink("INTERRUP.IDX");unlink("INTERRUP.CNT");

   fclose(fd);

	printf("OK\n\nDONE.\n");
	putchar(7);
}
