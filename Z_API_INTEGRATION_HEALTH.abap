*&---------------------------------------------------------------------*
*& Report Z_API_INTEGRATION_HEALTH
*&---------------------------------------------------------------------*
* Author - HXS0615 , Harsh Sharma
**********************************************************************
REPORT z_api_integration_health.

INCLUDE: z_api_data_dec,
         z_api_sel_screen,
         z_api_cls_logic.

START-OF-SELECTION.
  NEW lcl_integration_health( )->run( ).
