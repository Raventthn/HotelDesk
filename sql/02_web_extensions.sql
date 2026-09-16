-- Các SP deadlock cũ đã được tách khỏi source sản phẩm.
-- Nút "Đặt phòng lỗi" hiện chạy trên QL_KhachSan và được cài bằng:
--   06_install_booking_race.sql
-- Giữ file này để các quy trình cài cũ không lỗi do thiếu entry point.
:on error exit
PRINT N'Không có đối tượng demo deadlock để cài. Dùng 06_install_booking_race.sql cho demo tranh chấp đặt phòng.';
