-- SQLCMD entry point. Run from the sql directory; see README.md for SSMS setup.
-- For SSMS, set SqlRoot below to the absolute path of this sql directory.
:setvar SqlRoot "."
:on error exit

:r "$(SqlRoot)/schema/01_booking_schema.sql"
:r "$(SqlRoot)/product/view/vw_KiemTraLichBooking.sql"
:r "$(SqlRoot)/product/view/vw_BaoCao_DoanhThu_LoaiPhong.sql"
:r "$(SqlRoot)/product/view/vw_BookingChoNhanPhong.sql"
:r "$(SqlRoot)/product/view/vw_GiamSat_LichPhong.sql"
:r "$(SqlRoot)/product/view/vw_KhachDangLuuTru.sql"
:r "$(SqlRoot)/product/view/vw_LichSuGiaoDichBooking.sql"
:r "$(SqlRoot)/product/view/vw_QuyetToanBooking.sql"
:r "$(SqlRoot)/product/view/vw_TraCuuPhong.sql"
:r "$(SqlRoot)/product/procedures/SP_ThemKhachHang.sql"
:r "$(SqlRoot)/product/procedures/sp_TaoKhachHangTuThongTin.sql"
:r "$(SqlRoot)/product/procedures/sp_ThemLoaiPhong.sql"
:r "$(SqlRoot)/product/procedures/sp_CapNhatGiaLoaiPhong.sql"
:r "$(SqlRoot)/product/procedures/sp_NhanPhong.sql"
:r "$(SqlRoot)/product/procedures/sp_TraPhong.sql"
:r "$(SqlRoot)/product/procedures/sp_DatCoc.sql"
:r "$(SqlRoot)/product/procedures/sp_HuyBooking.sql"
:r "$(SqlRoot)/product/procedures/SP_KhoiTao_LuoiNgay.sql"
:r "$(SqlRoot)/product/procedures/SP_DatPhong.sql"
:r "$(SqlRoot)/product/procedures/sp_NoShow_NhaPhong.sql"

EXEC dbo.SP_KhoiTao_LuoiNgay @SoNgayCanSinh = 366;
GO

-- Remove replaced objects only after all replacements were installed successfully.
:r "$(SqlRoot)/schema/02_remove_replaced_objects.sql"
:r "$(SqlRoot)/schema/03_booking_race_demo.sql"
:r "$(SqlRoot)/product/view/vw_GiamSat_TrangThaiDatPhong.sql"
:r "$(SqlRoot)/procedures/sp_DatPhong_KhongBaoVe.sql"
:r "$(SqlRoot)/procedures/sp_DatPhong_Deadlock.sql"
:r "$(SqlRoot)/procedures/sp_TraPhongDemo.sql"
:r "$(SqlRoot)/procedures/sp_Demo_NonRepeat_Phantom.sql"
