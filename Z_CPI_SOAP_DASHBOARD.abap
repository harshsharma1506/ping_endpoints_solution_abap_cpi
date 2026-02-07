*&---------------------------------------------------------------------*
*& Report Z_CPI_SOAP_DASHBOARD
*&---------------------------------------------------------------------*
REPORT z_cpi_soap_dashboard.

CLASS lcl_dashboard DEFINITION.

  PUBLIC SECTION.
    METHODS run.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_out,
             light        TYPE c LENGTH 1, " 1=Red, 2=Yellow, 3=Green
             logical_port TYPE srt_lp-lp_name,
             service      TYPE srt_lp-service_name,
             status       TYPE string,
             trend        TYPE string,
             last_check   TYPE string,
             last_ok      TYPE string,
             endpoint     TYPE string,
           END OF ty_out.

    TYPES: BEGIN OF ty_port,
             lp_name      TYPE srt_lp-lp_name,
             service_name TYPE srt_lp-service_name,
             url          TYPE string,
           END OF ty_port.

    DATA: mt_out   TYPE TABLE OF ty_out,
          mt_ports TYPE TABLE OF ty_port.

    METHODS discover_ports.
    METHODS fetch_bal_data.
    METHODS prepare_alv_data.
    METHODS display_alv.

    METHODS map_status
      IMPORTING iv_msgty TYPE symsgty
      EXPORTING ev_status TYPE string
                ev_light  TYPE c.

    METHODS map_trend
      IMPORTING iv_latest TYPE symsgty
                iv_prev   TYPE symsgty
      RETURNING VALUE(rv_trend) TYPE string.

ENDCLASS.

CLASS lcl_dashboard IMPLEMENTATION.

  METHOD run.
    discover_ports( ).
    fetch_bal_data( ).
    prepare_alv_data( ).
    display_alv( ).
  ENDMETHOD.

  METHOD discover_ports.
    SELECT lp~lp_name, lp~service_name, url~url
      FROM srt_lp AS lp
      INNER JOIN srt_lp_url AS url ON lp~lp_name = url~lp_name
      WHERE url~url LIKE '%hana.ondemand.com%'
      INTO TABLE @mt_ports.
  ENDMETHOD.

  METHOD fetch_bal_data.
    DATA: ls_filter TYPE bal_s_lfil,
          lt_hdr    TYPE balhdr_t,
          lt_msgs   TYPE bal_t_mscl,
          lt_out    TYPE TABLE OF ty_out.

    APPEND VALUE #( sign = 'I' option = 'EQ' low = 'ZCPI_MON' ) TO ls_filter-object.
    APPEND VALUE #( sign = 'I' option = 'EQ' low = 'SOAP_CONN' ) TO ls_filter-subobject.
    " Last 30 days
    APPEND VALUE #( sign = 'I' option = 'GE' low = sy-datum - 30 ) TO ls_filter-aldate.

    CALL FUNCTION 'BAL_DB_SEARCH'
      EXPORTING
        i_s_log_filter = ls_filter
      IMPORTING
        e_t_log_header = lt_hdr
      EXCEPTIONS
        OTHERS         = 1.

    IF sy-subrc <> 0 OR lt_hdr IS INITIAL.
      RETURN.
    ENDIF.

    CALL FUNCTION 'BAL_DB_LOAD'
      EXPORTING
        i_t_log_header = lt_hdr
      IMPORTING
        e_t_msg        = lt_msgs
      EXCEPTIONS
        OTHERS         = 1.

    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    " Sort messages by Logical Port (msgv1) and then by Date/Time (descending)
    " We need to join msg with hdr for date/time.
    TYPES: BEGIN OF ty_msg_full,
             lp_name TYPE srt_lp-lp_name,
             msgty   TYPE symsgty,
             datum   TYPE aldate,
             uzeit   TYPE altime,
           END OF ty_msg_full.
    DATA: lt_msg_full TYPE TABLE OF ty_msg_full.

    LOOP AT lt_msgs INTO DATA(ls_msg).
      READ TABLE lt_hdr INTO DATA(ls_hdr) WITH KEY lognumber = ls_msg-lognumber.
      IF sy-subrc = 0.
        APPEND VALUE #( lp_name = ls_msg-msgv1
                        msgty   = ls_msg-msgty
                        datum   = ls_hdr-aldate
                        uzeit   = ls_hdr-altime ) TO lt_msg_full.
      ENDIF.
    ENDLOOP.

    SORT lt_msg_full BY lp_name ASC datum DESC uzeit DESC.

    " Now prepare mt_out based on mt_ports and processed logs
    LOOP AT mt_ports INTO DATA(ls_port).
      DATA(ls_out) = VALUE ty_out( logical_port = ls_port-lp_name
                                   service      = ls_port-service_name
                                   endpoint     = ls_port-url
                                   status       = 'UNKNOWN'
                                   light        = '2' ).

      DATA: lv_latest_sev TYPE symsgty,
            lv_prev_sev   TYPE symsgty,
            lv_found      TYPE abap_bool.

      LOOP AT lt_msg_full INTO DATA(ls_m) WHERE lp_name = ls_port-lp_name.
        IF lv_found = abap_false.
          lv_latest_sev = ls_m-msgty.
          ls_out-last_check = |{ ls_m-datum DATE = ENVIRONMENT } { ls_m-uzeit TIME = ENVIRONMENT }|.
          lv_found = abap_true.

          map_status(
            EXPORTING iv_msgty = ls_m-msgty
            IMPORTING ev_status = ls_out-status
                      ev_light  = ls_out-light ).
        ELSEIF lv_prev_sev IS INITIAL.
          lv_prev_sev = ls_m-msgty.
        ENDIF.

        IF ls_m-msgty = 'S' AND ls_out-last_ok IS INITIAL.
          ls_out-last_ok = |{ ls_m-datum DATE = ENVIRONMENT } { ls_m-uzeit TIME = ENVIRONMENT }|.
        ENDIF.

        IF lv_found = abap_true AND lv_prev_sev IS NOT INITIAL AND ls_out-last_ok IS NOT INITIAL.
          EXIT.
        ENDIF.
      ENDLOOP.

      ls_out-trend = map_trend( iv_latest = lv_latest_sev iv_prev = lv_prev_sev ).

      APPEND ls_out TO mt_out.
    ENDLOOP.
  ENDMETHOD.

  METHOD prepare_alv_data.
    " Data already prepared in fetch_bal_data for performance
  ENDMETHOD.

  METHOD map_status.
    CASE iv_msgty.
      WHEN 'S'. ev_status = 'OK'.        ev_light = '3'.
      WHEN 'W'. ev_status = 'AUTH'.      ev_light = '2'.
      WHEN 'E'. ev_status = 'CPI_ERROR'. ev_light = '1'.
      WHEN 'A'. ev_status = 'DOWN'.      ev_light = '1'.
      WHEN OTHERS. ev_status = 'UNKNOWN'. ev_light = '2'.
    ENDCASE.
  ENDMETHOD.

  METHOD map_trend.
    IF iv_latest IS INITIAL.
      RETURN.
    ENDIF.

    IF iv_prev IS INITIAL.
      rv_trend = '→'.
      RETURN.
    ENDIF.

    DATA(lv_lat_val) = SWITCH i( iv_latest WHEN 'S' THEN 1 WHEN 'W' THEN 2 WHEN 'E' THEN 3 WHEN 'A' THEN 4 ELSE 9 ).
    DATA(lv_pre_val) = SWITCH i( iv_prev   WHEN 'S' THEN 1 WHEN 'W' THEN 2 WHEN 'E' THEN 3 WHEN 'A' THEN 4 ELSE 9 ).

    IF lv_lat_val < lv_pre_val.
      rv_trend = '↑'.
    ELSEIF lv_lat_val > lv_pre_val.
      rv_trend = '↓'.
    ELSE.
      rv_trend = '→'.
    ENDIF.
  ENDMETHOD.

  METHOD display_alv.
    DATA: lo_alv      TYPE REF TO cl_salv_table,
          lo_columns  TYPE REF TO cl_salv_columns_table,
          lo_column   TYPE REF TO cl_salv_column_table.

    TRY.
        cl_salv_table=>factory(
          IMPORTING
            r_salv_table = lo_alv
          CHANGING
            t_table      = mt_out ).

        lo_columns = lo_alv->get_columns( ).
        lo_columns->set_optimize( abap_true ).

        " Set Exception Column (Traffic Lights)
        lo_columns->set_exception_column( 'LIGHT' ).

        " Rename columns
        lo_column ?= lo_columns->get_column( 'LOGICAL_PORT' ).
        lo_column->set_short_text( 'Log.Port' ).
        lo_column->set_medium_text( 'Logical Port' ).
        lo_column->set_long_text( 'Logical Port Name' ).

        lo_column ?= lo_columns->get_column( 'SERVICE' ).
        lo_column->set_long_text( 'Service Name' ).

        lo_column ?= lo_columns->get_column( 'TREND' ).
        lo_column->set_short_text( 'Trend' ).
        lo_column->set_alignment( if_salv_c_alignment=>centered ).

        lo_column ?= lo_columns->get_column( 'STATUS' ).
        lo_column->set_short_text( 'Status' ).

        lo_column ?= lo_columns->get_column( 'LAST_CHECK' ).
        lo_column->set_long_text( 'Last Check Timestamp' ).

        lo_column ?= lo_columns->get_column( 'LAST_OK' ).
        lo_column->set_long_text( 'Last OK Timestamp' ).

        lo_column ?= lo_columns->get_column( 'ENDPOINT' ).
        lo_column->set_long_text( 'CPI Endpoint URL' ).

        lo_alv->display( ).
      CATCH cx_salv_msg.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.

START-OF-SELECTION.
  NEW lcl_dashboard( )->run( ).

