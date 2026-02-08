*&---------------------------------------------------------------------*
*&  Include           Z_API_SEL_SCREEN
*&---------------------------------------------------------------------*
*----------------------------------------------------------------------*
* SELECTION SCREEN
*----------------------------------------------------------------------*
SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE text-t01.
PARAMETERS: rb_mon  RADIOBUTTON GROUP g1 DEFAULT 'X' USER-COMMAND mode,
            rb_dash RADIOBUTTON GROUP g1.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE text-t02.
SELECT-OPTIONS: s_serv FOR it_srt-proxy_class,
                s_lp   FOR it_srt-lp_name.
DATA: gv_stat_dummy TYPE ty_status_text.
SELECT-OPTIONS: s_stat FOR gv_stat_dummy NO-DISPLAY.
SELECTION-SCREEN END OF BLOCK b2.
