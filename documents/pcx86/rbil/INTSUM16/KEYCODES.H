//*********************************************************
//  KEYCODES.H - BIOS scan codes for keyboard              
//                                                         
//  Compiled by:  Daniel D. Miller                         
//  Last Update:  August 23, 1994                          
//                                                         
//*********************************************************

#define  Key_F1         0x3B00
#define  Key_ShF1       0x5400
#define  Key_CF1        0x5E00
#define  Key_AltF1      0x6800

#define  Key_F2         0x3C00
#define  Key_ShF2       0x5500
#define  Key_CF2        0x5F00
#define  Key_AltF2      0x6900

#define  Key_F3         0x3D00
#define  Key_ShF3       0x5600
#define  Key_CF3        0x6000
#define  Key_AltF3      0x6A00

#define  Key_F4         0x3E00
#define  Key_ShF4       0x5700
#define  Key_CF4        0x6100
#define  Key_AltF4      0x6B00

#define  Key_F5         0x3F00
#define  Key_ShF5       0x5800
#define  Key_CF5        0x6200
#define  Key_AltF5      0x6C00

#define  Key_F6         0x4000
#define  Key_ShF6       0x5900
#define  Key_CF6        0x6300
#define  Key_AltF6      0x6D00

#define  Key_F7         0x4100
#define  Key_ShF7       0x5A00
#define  Key_CF7        0x6400
#define  Key_AltF7      0x6E00

#define  Key_F8         0x4200
#define  Key_ShF8       0x5B00
#define  Key_CF8        0x6500
#define  Key_AltF8      0x6F00

#define  Key_F9         0x4300
#define  Key_ShF9       0x5C00
#define  Key_CF9        0x6600
#define  Key_AltF9      0x7000

#define  Key_F10        0x4400
#define  Key_ShF10      0x5D00
#define  Key_CF10       0x6700
#define  Key_AltF10     0x7100

#define  Key_F11        0x8500
#define  Key_ShF11      0x8700
#define  Key_CF11       0x8900
#define  Key_AltF11     0x8B00

#define  Key_F12        0x8600
#define  Key_ShF12      0x8800
#define  Key_CF12       0x8A00
#define  Key_AltF12     0x8C00

#define  Key_END        0x4F00
#define  Key_ShEND      0x4F31
#define  Key_CEND       0x7500

#define  Key_DOWN       0x5000
#define  Key_ShDOWN     0x5032
#define  Key_CDOWN      0x9100

#define  Key_PGDN       0x5100
#define  Key_ShPGDN     0x5133
#define  Key_CPGDN      0x7600

#define  Key_LEFT       0x4B00
#define  Key_ShLEFT     0x4B34
#define  Key_CLEFT      0x7300

#define  Key_SPACE      0x3920
#define  Key_KEYPAD5    0x4C00
#define  Key_ShKEYPAD5  0x4C35
#define  Key_CKEYPAD5   0x8F00

#define  Key_RIGHT      0x4D00
#define  Key_ShRIGHT    0x4D36
#define  Key_CRIGHT     0x7400

#define  Key_HOME       0x4700
#define  Key_ShHOME     0x4737
#define  Key_CHOME      0x7700

#define  Key_UP         0x4800
#define  Key_ShUP       0x4838
#define  Key_CUP        0x8D00

#define  Key_PGUP       0x4900
#define  Key_ShPGUP     0x4939
#define  Key_CPGUP      0x8400

#define  Key_INS        0x5200
#define  Key_ShINS      0x5230
#define  Key_CINS       0x9200

#define  Key_DEL        0x5300
#define  Key_ShDEL      0x532E
#define  Key_CDEL       0x9300

#define  Key_GHOME      0x47E0
#define  Key_ShGHOME    0x47E0
#define  Key_CGHOME     0x77E0
#define  Key_AltGHOME   0x9700

#define  Key_GEND       0x4FE0
#define  Key_ShGEND     0x4FE0
#define  Key_CGEND      0x75E0
#define  Key_AltGEND    0x9F00

#define  Key_GPGUP      0x49E0
#define  Key_ShGPGUP    0x49E0
#define  Key_CGPGUP     0x84E0
#define  Key_AltGPGUP   0x9900

#define  Key_GPGDN      0x51E0
#define  Key_ShGPGDN    0x51E0
#define  Key_CGPGDN     0x76E0
#define  Key_AltGPGDN   0x0A100

#define  Key_GRIGHT     0x4DE0
#define  Key_ShGRIGHT   0x4DE0
#define  Key_CGRIGHT    0x74E0
#define  Key_AltGRIGHT  0x9D00

#define  Key_GLEFT      0x4BE0
#define  Key_ShGLEFT    0x4BE0
#define  Key_CGLEFT     0x73E0
#define  Key_AltGLEFT   0x9B00

#define  Key_GUP        0x48E0
#define  Key_ShGUP      0x48E0
#define  Key_CGUP       0x8DE0
#define  Key_AltGUP     0x9800

#define  Key_GSTAR      0x372A

#define  Key_GDOWN      0x50E0
#define  Key_ShGDOWN    0x50E0
#define  Key_CGDOWN     0x91E0
#define  Key_AltGDOWN   0x0A000

#define  Key_GINS       0x52E0
#define  Key_ShGINS     0x52E0
#define  Key_CGINS      0x92E0
#define  Key_AltGINS    0x0A200

#define  Key_GDEL       0x53E0
#define  Key_ShGDEL     0x53E0
#define  Key_CGDEL      0x93E0
#define  Key_AltGDEL    0x0A300

#define  Key_ESC        0x011B
#define  Key_ShESC      0x011B
#define  Key_CESC       0x011B
#define  Key_AltESC     0x0100

#define  Key_TAB        0x0F09
#define  Key_ShTAB      0x0F00
#define  Key_CTAB       0x9400
#define  Key_AltTAB     0x0A500

#define  Key_ENTER      0x1C0D
#define  Key_ShENTER    0x1C0D
#define  Key_CENTER     0x1C0A
#define  Key_AltENTER   0x1C00

#define  Key_GENTER     0x0E00D
#define  Key_ShGENTER   0x0E00D
#define  Key_CGENTER    0x0E00A
#define  Key_AltGENTER  0x0A600

#define  Key_BSPACE     0x0E08
#define  Key_ShBSPACE   0x0E08
#define  Key_CBSPACE    0x0E7F
#define  Key_AltBSPACE  0x0E00

#define  Key_A       0x1E41
#define  Key_ShA     0x1E41
#define  Key_a       0x1E61
#define  Key_CA      0x1E01
#define  Key_AltA    0x1E00

#define  Key_B       0x3042
#define  Key_ShB     0x3042
#define  Key_b       0x3062
#define  Key_CB      0x3002
#define  Key_AltB    0x3000

#define  Key_C       0x2E43
#define  Key_ShC     0x2E43
#define  Key_c       0x2E63
#define  Key_CC      0x2E03
#define  Key_AltC    0x2E00

#define  Key_D       0x2044
#define  Key_ShD     0x2044
#define  Key_d       0x2064
#define  Key_CD      0x2004
#define  Key_AltD    0x2000

#define  Key_E       0x1245
#define  Key_ShE     0x1245
#define  Key_e       0x1265
#define  Key_CE      0x1205
#define  Key_AltE    0x1200

#define  Key_F       0x2146
#define  Key_ShF     0x2146
#define  Key_f       0x2166
#define  Key_CF      0x2106
#define  Key_AltF    0x2100

#define  Key_G       0x2247
#define  Key_ShG     0x2247
#define  Key_g       0x2267
#define  Key_CG      0x2207
#define  Key_AltG    0x2200

#define  Key_H       0x2348
#define  Key_ShH     0x2348
#define  Key_h       0x2368
#define  Key_CH      0x2308
#define  Key_AltH    0x2300

#define  Key_I       0x1749
#define  Key_ShI     0x1749
#define  Key_i       0x1769
#define  Key_CI      0x1709
#define  Key_AltI    0x1700

#define  Key_J       0x244A
#define  Key_ShJ     0x244A
#define  Key_j       0x246A
#define  Key_CJ      0x240A
#define  Key_AltJ    0x2400

#define  Key_K       0x254B
#define  Key_ShK     0x254B
#define  Key_k       0x256B
#define  Key_CK      0x250B
#define  Key_AltK    0x2500

#define  Key_L       0x264C
#define  Key_ShL     0x264C
#define  Key_l       0x266C
#define  Key_CL      0x260C
#define  Key_AltL    0x2600

#define  Key_M       0x324D
#define  Key_ShM     0x324D
#define  Key_m       0x326D
#define  Key_CM      0x320D
#define  Key_AltM    0x3200

#define  Key_N       0x314E
#define  Key_ShN     0x314E
#define  Key_n       0x316E
#define  Key_CN      0x310E
#define  Key_AltN    0x3100

#define  Key_O       0x184F
#define  Key_ShO     0x184F
#define  Key_o       0x186F
#define  Key_CO      0x180F
#define  Key_AltO    0x1800

#define  Key_P       0x1950
#define  Key_ShP     0x1950
#define  Key_p       0x1970
#define  Key_CP      0x1910
#define  Key_AltP    0x1900

#define  Key_Q       0x1051
#define  Key_ShQ     0x1051
#define  Key_q       0x1071
#define  Key_CQ      0x1011
#define  Key_AltQ    0x1000

#define  Key_R       0x1352
#define  Key_ShR     0x1352
#define  Key_r       0x1372
#define  Key_CR      0x1312
#define  Key_AltR    0x1300

#define  Key_S       0x1F53
#define  Key_ShS     0x1F53
#define  Key_s       0x1F73
#define  Key_CS      0x1F13
#define  Key_AltS    0x1F00

#define  Key_T       0x1454
#define  Key_ShT     0x1454
#define  Key_t       0x1474
#define  Key_CT      0x1414
#define  Key_AltT    0x1400

#define  Key_U       0x1655
#define  Key_ShU     0x1655
#define  Key_u       0x1675
#define  Key_CU      0x1615
#define  Key_AltU    0x1600

#define  Key_V       0x2F56
#define  Key_ShV     0x2F56
#define  Key_v       0x2F76
#define  Key_CV      0x2F16
#define  Key_AltV    0x2F00

#define  Key_W       0x1157
#define  Key_ShW     0x1157
#define  Key_w       0x1177
#define  Key_CW      0x1117
#define  Key_AltW    0x1100

#define  Key_X       0x2D58
#define  Key_ShX     0x2D58
#define  Key_x       0x2D78
#define  Key_CX      0x2D18
#define  Key_AltX    0x2D00

#define  Key_Y       0x1559
#define  Key_ShY     0x1559
#define  Key_y       0x1579
#define  Key_CY      0x1519
#define  Key_AltY    0x1500

#define  Key_Z       0x2C5A
#define  Key_ShZ     0x2C5A
#define  Key_z       0x2C7A
#define  Key_CZ      0x2C1A
#define  Key_AltZ    0x2C00

#define  Key_1       0x0231
#define  Key_Sh1     0x0221
#define  Key_Alt1    0x7800

#define  Key_2       0x0332
#define  Key_Sh2     0x0340
#define  Key_C2      0x0300
#define  Key_Alt2    0x7900

#define  Key_3       0x0433
#define  Key_Sh3     0x0423
#define  Key_Alt3    0x7A00

#define  Key_4       0x0534
#define  Key_Sh4     0x0524
#define  Key_Alt4    0x7B00

#define  Key_5       0x0635
#define  Key_Sh5     0x0625
#define  Key_Alt5    0x7C00

#define  Key_6       0x0736
#define  Key_Sh6     0x075E
#define  Key_C6      0x071E
#define  Key_Alt6    0x7D00

#define  Key_7       0x0837
#define  Key_Sh7     0x0826
#define  Key_Alt7    0x7E00

#define  Key_8       0x0938
#define  Key_Sh8     0x092A
#define  Key_Alt8    0x7F00

#define  Key_9       0x0A39
#define  Key_Sh9     0x0A28
#define  Key_Alt9    0x8000

#define  Key_0       0x0B30
#define  Key_Sh0     0x0B29
#define  Key_Alt0    0x8100

#define  Key_MINUS      0x0C2D
#define  Key_ShMINUS    0x0C5F
#define  Key_CMINUS     0x0C1F
#define  Key_AltMINUS   0x8200

#define  Key_EQUALS     0x0D3D
#define  Key_PLUS       0x0D2B
#define  Key_AltEQUALS  0x8300

#define  Key_LBrkt      0x1A5B
#define  Key_ShLBrkt    0x1A7B
#define  Key_CLBrkt     0x1A1B
#define  Key_AltLBrkt   0x1A00

#define  Key_RBrkt      0x1B5D
#define  Key_ShRBrkt    0x1B7D
#define  Key_CRBrkt     0x1B1D
#define  Key_AltRBrkt   0x1B00

#define  Key_Comma      0x332C
#define  Key_LessThan   0x333C
#define  Key_AltComma   0x3300

#define  Key_Period     0x342E
#define  Key_GrtrThan   0x343E
#define  Key_AltPeriod  0x3400

#define  Key_Slash      0x352F
#define  Key_QMark      0x353F
#define  Key_AltSlash   0x3500

#define  Key_GPlus      0x4E2B
#define  Key_ShGPlus    0x4E2B
#define  Key_CGPlus     0x9000
#define  Key_AltGPlus   0x4E00

#define  Key_GMinus     0x4A2D
#define  Key_ShGMinus   0x4A2D
#define  Key_CGMinus    0x8E00
#define  Key_AltGMinus  0x4A00
