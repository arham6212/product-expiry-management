#!/bin/bash
cat db_schema.sql | awk '/CREATE OR REPLACE FUNCTION "public"\."create_product_for_barcode"/,/\$_\$;/' > rpc1.txt
cat db_schema.sql | awk '/CREATE OR REPLACE FUNCTION "public"\."create_manual_product_for_barcode"/,/\$\$;/' > rpc2.txt
