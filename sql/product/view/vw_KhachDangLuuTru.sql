USE QL_KhachSan;
GO

CREATE OR ALTER VIEW dbo.vw_KhachDangLuuTru
AS
WITH LichTheoPhong AS (
    SELECT
        pn.MaDatPhong,
        pn.MaPhong,
        MIN(pn.Ngay) AS NgayNhanDuKien,
        DATEADD(DAY, 1, MAX(pn.Ngay)) AS NgayTraDuKien,
        COUNT(*) AS SoDemDaDat
    FROM dbo.PHONG_NGAY AS pn
    WHERE pn.MaDatPhong IS NOT NULL
    GROUP BY pn.MaDatPhong, pn.MaPhong
)
SELECT
    dp.MaDatPhong,
    dp.MaKH,
    kh.HoTen AS TenKhachHang,
    kh.SDT,
    kh.CCCD,
    p.MaPhong,
    p.SoPhong,
    lp.MaLoai,
    lp.TenLoai AS TenLoaiPhong,
    lich.NgayNhanDuKien,
    lich.NgayTraDuKien,
    ISNULL(lich.SoDemDaDat, 0) AS SoDemDaDat,
    dp.TongTien AS TongTienBooking,
    dp.TrangThai,
    dp.Version,
    CAST(CASE
        WHEN lich.MaPhong IS NULL OR valid.LichHopLe=0 THEN 1 ELSE 0
    END AS BIT) AS ThieuLichPhong,
    CAST(CASE
        WHEN lich.NgayTraDuKien = CONVERT(DATE, GETDATE())
            THEN 1 ELSE 0
    END AS BIT) AS DuKienTraHomNay,
    CAST(CASE
        WHEN lich.NgayTraDuKien < CONVERT(DATE, GETDATE())
            THEN 1 ELSE 0
    END AS BIT) AS QuaNgayTraDuKien,
    CASE
        WHEN lich.NgayTraDuKien < CONVERT(DATE, GETDATE())
            THEN DATEDIFF(DAY, lich.NgayTraDuKien, CONVERT(DATE, GETDATE()))
        ELSE 0
    END AS SoNgayQuaHan
FROM dbo.DATPHONG AS dp
INNER JOIN dbo.KHACHHANG AS kh ON kh.MaKH = dp.MaKH
LEFT JOIN LichTheoPhong AS lich ON lich.MaDatPhong = dp.MaDatPhong
LEFT JOIN dbo.PHONG AS p ON p.MaPhong = lich.MaPhong
LEFT JOIN dbo.LOAIPHONG AS lp ON lp.MaLoai = p.MaLoai
LEFT JOIN dbo.vw_KiemTraLichBooking valid ON valid.MaDatPhong=dp.MaDatPhong
WHERE dp.TrangThai = N'Đang ở';
GO
