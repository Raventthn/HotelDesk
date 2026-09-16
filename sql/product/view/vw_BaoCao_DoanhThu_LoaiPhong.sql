USE QL_KhachSan;
GO
-- New bookings use immutable room/price detail. Legacy bookings use explicitly marked estimates.
CREATE OR ALTER VIEW dbo.vw_BaoCao_DoanhThu_LoaiPhong AS
WITH LegacyWeights AS (
    SELECT pn.MaDatPhong,p.MaLoai,CAST(SUM(lp.GiaCoBan) AS DECIMAL(28,8)) AS TrongSo
    FROM dbo.PHONG_NGAY pn JOIN dbo.PHONG p ON p.MaPhong=pn.MaPhong
    JOIN dbo.LOAIPHONG lp ON lp.MaLoai=p.MaLoai
    WHERE pn.MaDatPhong IS NOT NULL
      AND NOT EXISTS(SELECT 1 FROM dbo.DATPHONG_PHONG d WHERE d.MaDatPhong=pn.MaDatPhong)
    GROUP BY pn.MaDatPhong,p.MaLoai
), LegacyTotals AS (
    SELECT w.*,CAST(SUM(TrongSo) OVER(PARTITION BY MaDatPhong) AS DECIMAL(28,8)) AS TongTrongSo,
        COUNT(*) OVER(PARTITION BY MaDatPhong) AS SoLoai,
        ROW_NUMBER() OVER(PARTITION BY MaDatPhong ORDER BY TrongSo DESC,MaLoai) AS ThuTu
    FROM LegacyWeights w
), Rounded AS (
    SELECT w.MaDatPhong,w.MaLoai,w.ThuTu,dp.TongTien,
        CAST(ROUND(dp.TongTien * (CASE WHEN w.TongTrongSo=0 THEN
            CAST(1 AS DECIMAL(28,8))/w.SoLoai ELSE w.TrongSo/w.TongTrongSo END),2) AS DECIMAL(18,2)) AS PhanBo
    FROM LegacyTotals w JOIN dbo.DATPHONG dp ON dp.MaDatPhong=w.MaDatPhong
    WHERE dp.TrangThai IN(N'Đã đặt',N'Đang ở',N'Đã trả') AND dp.TongTien>=0
), Amounts AS (
    SELECT d.MaDatPhong,d.MaLoai,SUM(d.ThanhTien) AS GiaTri,0 AS UocTinh
    FROM dbo.DATPHONG_PHONG d JOIN dbo.DATPHONG dp ON dp.MaDatPhong=d.MaDatPhong
    WHERE dp.TrangThai IN(N'Đã đặt',N'Đang ở',N'Đã trả') GROUP BY d.MaDatPhong,d.MaLoai
    UNION ALL
    SELECT MaDatPhong,MaLoai,
        PhanBo + CASE WHEN ThuTu=1 THEN TongTien-SUM(PhanBo) OVER(PARTITION BY MaDatPhong) ELSE 0 END,1
    FROM Rounded
)
SELECT lp.MaLoai,lp.TenLoai,COUNT(DISTINCT a.MaDatPhong) AS SoLuongBooking,
    CAST(COALESCE(SUM(a.GiaTri),0) AS DECIMAL(18,2)) AS TongDoanhThu,
    COUNT(DISTINCT CASE WHEN a.UocTinh=1 THEN a.MaDatPhong END) AS SoBookingUocTinh
FROM dbo.LOAIPHONG lp LEFT JOIN Amounts a ON a.MaLoai=lp.MaLoai
GROUP BY lp.MaLoai,lp.TenLoai;
GO
