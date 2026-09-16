-- SQLCMD entry point. Run from the sql directory; see README.md for SSMS setup.
-- For SSMS, set SqlRoot below to the absolute path of this sql directory.
--:setvar SqlRoot "."
:setvar SqlRoot C:\Users\Dell\OneDrive\HotelDesk-ASPNET-Blazor\sql
:on error exit

:r ".\schema\01_booking_schema.sql"
:r ".\product\view\vw_KiemTraLichBooking.sql"
:r ".\product\view\vw_BaoCao_DoanhThu_LoaiPhong.sql"
:r ".\product\view\vw_BookingChoNhanPhong.sql"
:r ".\product\view\vw_GiamSat_LichPhong.sql"
:r ".\product\view\vw_KhachDangLuuTru.sql"
:r ".\product\view\vw_LichSuGiaoDichBooking.sql"
:r ".\product\view\vw_QuyetToanBooking.sql"
:r ".\product\view\vw_TraCuuPhong.sql"
:r ".\product\procedures\SP_ThemKhachHang.sql"
:r ".\product\procedures\sp_TaoKhachHangTuThongTin.sql"
:r ".\product\procedures\sp_ThemLoaiPhong.sql"
:r ".\product\procedures\sp_CapNhatGiaLoaiPhong.sql"
:r ".\product\procedures\sp_NhanPhong.sql"
:r ".\product\procedures\sp_TraPhong.sql"
:r ".\product\procedures\sp_DatCoc.sql"
:r ".\product\procedures\sp_HuyBooking.sql"
:r ".\product\procedures\SP_KhoiTao_LuoiNgay.sql"
:r ".\product\procedures\SP_DatPhong.sql"
:r ".\product\procedures\sp_NoShow_NhaPhong.sql"

EXEC dbo.SP_KhoiTao_LuoiNgay @SoNgayCanSinh = 366;
GO

-- Remove replaced objects only after all replacements were installed successfully.
:r ".\schema\02_remove_replaced_objects.sql"
:r ".\schema\03_booking_race_demo.sql"
:r ".\product\view\vw_GiamSat_TrangThaiDatPhong.sql"
:r ".\procedures\sp_DatPhong_KhongBaoVe.sql"
:r ".\procedures\sp_DatPhong_Deadlock.sql"
:r ".\procedures\sp_TraPhongDemo.sql"
:r ".\procedures\sp_Demo_NonRepeat_Phantom.sql"
