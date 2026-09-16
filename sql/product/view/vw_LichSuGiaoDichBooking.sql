USE QL_KhachSan;
GO

CREATE OR ALTER VIEW dbo.vw_LichSuGiaoDichBooking
AS
SELECT
    tt.MaGD,
    tt.MaDatPhong,
    dp.MaKH,
    kh.HoTen AS TenKhachHang,
    kh.SDT,
    dp.TrangThai AS TrangThaiBookingHienTai,
    dp.PhiNoShow,
    dp.NgayXuLyNoShow,
    tt.NgayGD,
    tt.LoaiGiaoDich,
    tt.SoTien,
    CASE
        WHEN tt.LoaiGiaoDich IN (N'Đặt cọc', N'Thanh toán') THEN N'Thu'
        WHEN tt.LoaiGiaoDich = N'Hoàn tiền' THEN N'Hoàn'
        ELSE N'Không xác định'
    END AS HuongGiaoDich,
    CAST(CASE
        WHEN tt.SoTien IS NULL OR tt.SoTien <= 0 THEN NULL
        WHEN tt.LoaiGiaoDich IN (N'Đặt cọc', N'Thanh toán') THEN tt.SoTien
        WHEN tt.LoaiGiaoDich = N'Hoàn tiền' THEN -tt.SoTien
        ELSE NULL
    END AS DECIMAL(18, 2)) AS SoTienQuyDoi,
    CAST(CASE
        WHEN tt.LoaiGiaoDich IS NULL
          OR tt.LoaiGiaoDich NOT IN
             (N'Đặt cọc', N'Thanh toán', N'Hoàn tiền')
          OR tt.SoTien IS NULL OR tt.SoTien <= 0
            THEN 1
        ELSE 0
    END AS BIT) AS GiaoDichBatThuong,
    CAST(CASE
        WHEN tt.NgayGD IS NULL THEN 1 ELSE 0
    END AS BIT) AS ThieuThoiDiemGiaoDich
FROM dbo.THANHTOAN AS tt
INNER JOIN dbo.DATPHONG AS dp ON dp.MaDatPhong = tt.MaDatPhong
INNER JOIN dbo.KHACHHANG AS kh ON kh.MaKH = dp.MaKH;
GO
