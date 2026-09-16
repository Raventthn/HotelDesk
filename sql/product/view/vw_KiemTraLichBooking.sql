USE QL_KhachSan;
GO
-- Internal shared validation used by eligibility views and transactional procedures.
CREATE OR ALTER VIEW dbo.vw_KiemTraLichBooking AS
WITH Rooms AS (
    SELECT MaDatPhong, MaPhong, MIN(Ngay) AS NgayNhan, MAX(Ngay) AS NgayCuoi, COUNT_BIG(*) AS SoDem
    FROM dbo.PHONG_NGAY WHERE MaDatPhong IS NOT NULL GROUP BY MaDatPhong, MaPhong
), Bookings AS (
    SELECT MaDatPhong, COUNT_BIG(*) AS SoPhong, MIN(NgayNhan) AS NgayNhanMin, MAX(NgayNhan) AS NgayNhanMax,
        MIN(NgayCuoi) AS NgayCuoiMin, MAX(NgayCuoi) AS NgayCuoiMax,
        MAX(CASE WHEN SoDem <> DATEDIFF(DAY,NgayNhan,NgayCuoi)+1 THEN 1 ELSE 0 END) AS ThieuNgay
    FROM Rooms GROUP BY MaDatPhong
)
SELECT dp.MaDatPhong, CAST(CASE WHEN b.SoPhong=dp.SoLuongPhongDat
    AND b.NgayNhanMin=dp.NgayNhanDuKien AND b.NgayNhanMax=dp.NgayNhanDuKien
    AND b.NgayCuoiMin=DATEADD(DAY,-1,dp.NgayTraDuKien) AND b.NgayCuoiMax=DATEADD(DAY,-1,dp.NgayTraDuKien)
    AND b.ThieuNgay=0
    AND (NOT EXISTS(SELECT 1 FROM dbo.DATPHONG_PHONG d WHERE d.MaDatPhong=dp.MaDatPhong)
         OR ((SELECT COUNT_BIG(*) FROM dbo.DATPHONG_PHONG d WHERE d.MaDatPhong=dp.MaDatPhong)=b.SoPhong
             AND NOT EXISTS(SELECT 1 FROM dbo.DATPHONG_PHONG d WHERE d.MaDatPhong=dp.MaDatPhong
                 AND NOT EXISTS(SELECT 1 FROM Rooms r WHERE r.MaDatPhong=d.MaDatPhong AND r.MaPhong=d.MaPhong))))
    THEN 1 ELSE 0 END AS BIT) AS LichHopLe
FROM dbo.DATPHONG dp LEFT JOIN Bookings b ON b.MaDatPhong=dp.MaDatPhong;
GO
