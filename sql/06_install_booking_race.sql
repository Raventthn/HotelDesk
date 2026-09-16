-- Installs ONLY the race demonstration on the main QL_KhachSan database.
-- Existing booking/calendar tables and product procedures are not modified.
:on error exit
-- Run sqlcmd from the sql directory. In SSMS use absolute paths below.
:r ".\schema\03_booking_race_demo.sql"
:r ".\product\view\vw_GiamSat_TrangThaiDatPhong.sql"
:r ".\procedures\sp_DatPhong_KhongBaoVe.sql"
:r ".\procedures\sp_DatPhong_Deadlock.sql"
:r ".\procedures\sp_TraPhongDemo.sql"
:r ".\procedures\sp_Demo_NonRepeat_Phantom.sql"
