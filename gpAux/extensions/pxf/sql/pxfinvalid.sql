------------------------------------------------------------------
-- PXF invalid test
------------------------------------------------------------------

CREATE EXTERNAL TABLE pxf_invalid_test (a TEXT, b TEXT, c TEXT)
LOCATION ('pxf://default/tmp/dummy1?FRAGMENTER=DemoFragmenter&ACCESSOR=&RESOLVER=DemoTextResolver')
FORMAT 'TEXT' (DELIMITER ',');