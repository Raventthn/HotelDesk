USE QL_KhachSan;
GO


CREATE OR ALTER VIEW dbo.vw_TraCuuPhong
AS
SELECT
    p.MaPhong,
    p.SoPhong,
    lp.MaLoai,
    lp.TenLoai,
    lp.GiaCoBan,
    pn.Ngay,
    pn.MaDatPhong
FROM dbo.PHONG AS p
INNER JOIN dbo.LOAIPHONG AS lp ON lp.MaLoai = p.MaLoai
INNER JOIN dbo.PHONG_NGAY AS pn ON pn.MaPhong = p.MaPhong;
GO
