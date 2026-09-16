-- SQLCMD Mode. Run from sql directory; set SqlRoot in 01 for SSMS.
-- Retains bookings/payments; adds schema, updates product objects, removes replacements.
:on error exit
:r ".\01_install_views_and_procedures.sql"
