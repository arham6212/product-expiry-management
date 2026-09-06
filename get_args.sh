#!/bin/bash
cat db_schema.sql | grep -E 'CREATE OR REPLACE FUNCTION "public"\."create_product_for_barcode"'
cat db_schema.sql | grep -E 'CREATE OR REPLACE FUNCTION "public"\."create_manual_product_for_barcode"'
