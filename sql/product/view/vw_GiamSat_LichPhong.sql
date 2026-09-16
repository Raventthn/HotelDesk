USE QL_KhachSan;
GO

CREATE OR ALTER VIEW dbo.vw_GiamSat_LichPhong
AS

SELECT
    pn.MaPhong,
    p.SoPhong,
    lp.TenLoai,

    pn.Ngay,

    pn.MaDatPhong,

    dp.MaKH,
    kh.HoTen AS TenKhachHang,

    dp.TrangThai,

    dp.Version

FROM PHONG_NGAY pn

INNER JOIN PHONG p
    ON pn.MaPhong = p.MaPhong

INNER JOIN LOAIPHONG lp
    ON p.MaLoai = lp.MaLoai

LEFT JOIN DATPHONG dp
    ON pn.MaDatPhong = dp.MaDatPhong

LEFT JOIN KHACHHANG kh
    ON dp.MaKH = kh.MaKH;
GO
