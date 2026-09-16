USE QL_KhachSan;
GO

CREATE OR ALTER VIEW dbo.vw_BookingChoNhanPhong
AS
WITH LichTheoPhong AS (
    SELECT
        pn.MaDatPhong,
        pn.MaPhong,
        MIN(pn.Ngay) AS NgayNhan,
        MAX(pn.Ngay) AS NgayCuoi,
        COUNT(*) AS SoDem
    FROM dbo.PHONG_NGAY AS pn
    WHERE pn.MaDatPhong IS NOT NULL
    GROUP BY pn.MaDatPhong, pn.MaPhong
),
LichTheoBooking AS (
    SELECT
        lp.MaDatPhong,
        MIN(lp.NgayNhan) AS NgayNhanSomNhat,
        MAX(lp.NgayNhan) AS NgayNhanMuonNhat,
        DATEADD(DAY, 1, MAX(lp.NgayCuoi)) AS NgayTraDuKien,
        COUNT(*) AS SoLuongPhong,
        SUM(lp.SoDem) AS TongSoDemPhong
    FROM LichTheoPhong AS lp
    GROUP BY lp.MaDatPhong
)
SELECT
    dp.MaDatPhong,
    dp.MaKH,
    kh.HoTen AS TenKhachHang,
    kh.SDT,
    kh.CCCD,
    dp.MaNV AS MaNhanVienTao,
    dp.NgayTao,
    CASE
        WHEN lb.NgayNhanSomNhat = lb.NgayNhanMuonNhat
            THEN lb.NgayNhanSomNhat
        ELSE NULL
    END AS NgayNhanDuKien,
    lb.NgayTraDuKien,
    ISNULL(lb.SoLuongPhong, 0) AS SoLuongPhong,
    ISNULL(lb.TongSoDemPhong, 0) AS TongSoDemPhong,
    dp.TongTien,
    dp.TrangThai,
    dp.Version,
    dp.SoLuongPhongDat AS SoLuongPhongDuKien,
    valid.LichHopLe,
    CAST(CASE
        WHEN lb.SoLuongPhong > 0
         AND valid.LichHopLe=1
         AND NOT EXISTS(SELECT 1 FROM dbo.PHONG_NGAY mine
             JOIN dbo.PHONG_NGAY other ON other.MaPhong=mine.MaPhong AND other.MaDatPhong<>mine.MaDatPhong
             JOIN dbo.DATPHONG old ON old.MaDatPhong=other.MaDatPhong
             WHERE mine.MaDatPhong=dp.MaDatPhong AND old.TrangThai=N'Đang ở')
         AND lb.NgayNhanSomNhat = lb.NgayNhanMuonNhat
         AND lb.NgayNhanSomNhat = CONVERT(DATE, GETDATE())
         AND dp.TongTien IS NOT NULL
         AND dp.TongTien >= 0
            THEN 1
        ELSE 0
    END AS BIT) AS CoTheNhanPhong
FROM dbo.DATPHONG AS dp
INNER JOIN dbo.KHACHHANG AS kh ON kh.MaKH = dp.MaKH
LEFT JOIN LichTheoBooking AS lb ON lb.MaDatPhong = dp.MaDatPhong
LEFT JOIN dbo.vw_KiemTraLichBooking valid ON valid.MaDatPhong=dp.MaDatPhong
WHERE dp.TrangThai = N'Đã đặt';
GO
