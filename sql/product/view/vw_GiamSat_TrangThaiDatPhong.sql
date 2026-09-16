-- =====================================================================
-- sql/product/view/vw_GiamSat_TrangThaiDatPhong.sql
-- (View giám sát trạng thái booking, dùng để theo dõi khi demo các case)
-- =====================================================================
USE QL_KhachSan;
GO
CREATE OR ALTER VIEW dbo.vw_GiamSat_TrangThaiDatPhong
AS
SELECT
    dp.MaDatPhong,
    dp.TrangThai,
    dp.Version,
    dp.TongTien,
    kh.MaKH,
    kh.HoTen        AS TenKhach,
    nv.MaNV,
    nv.HoTen         AS TenNhanVien,
    dp.NgayNhanDuKien,
    dp.NgayTraDuKien,
    dp.NgayTraThucTe,
    (
        SELECT STRING_AGG(dpp.MaPhong, ', ') WITHIN GROUP (ORDER BY dpp.MaPhong)
        FROM dbo.DATPHONG_PHONG dpp
        WHERE dpp.MaDatPhong = dp.MaDatPhong
    ) AS DanhSachPhong,
    CASE
        WHEN dp.MaDatPhong LIKE 'DP_DEMO%' THEN N'Demo Concurrency'
        ELSE N'Nghiệp vụ'
    END AS Nhom,
    SYSDATETIME() AS ThoiDiemXem
FROM dbo.DATPHONG dp
INNER JOIN dbo.KHACHHANG kh ON kh.MaKH = dp.MaKH
INNER JOIN dbo.NHANVIEN nv ON nv.MaNV = dp.MaNV;
GO
