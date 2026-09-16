USE QL_KhachSan;
GO

-- Shared by fresh installation and upgrades. Existing booking/payment rows are retained.
IF TYPE_ID(N'dbo.DanhSachPhongDat') IS NULL
    EXEC(N'CREATE TYPE dbo.DanhSachPhongDat AS TABLE (MaPhong VARCHAR(10) NOT NULL PRIMARY KEY);');
GO
IF OBJECT_ID(N'dbo.Seq_MaDatPhong', N'SO') IS NULL
    CREATE SEQUENCE dbo.Seq_MaDatPhong AS INT START WITH 1 INCREMENT BY 1;
GO
IF OBJECT_ID(N'dbo.Seq_MaKhachHang', N'SO') IS NULL
    CREATE SEQUENCE dbo.Seq_MaKhachHang AS INT START WITH 1 INCREMENT BY 1;
GO
IF COL_LENGTH('dbo.THANHTOAN', 'MaGD') IS NOT NULL
   AND EXISTS
   (
       SELECT 1
       FROM sys.columns
       WHERE object_id = OBJECT_ID(N'dbo.THANHTOAN')
         AND name = N'MaGD'
         AND max_length < 30
   )
    ALTER TABLE dbo.THANHTOAN ALTER COLUMN MaGD VARCHAR(30) NOT NULL;
GO
IF COL_LENGTH('dbo.DATPHONG', 'NgayNhanDuKien') IS NULL
    ALTER TABLE dbo.DATPHONG ADD NgayNhanDuKien DATE NULL;
IF COL_LENGTH('dbo.DATPHONG', 'NgayTraDuKien') IS NULL
    ALTER TABLE dbo.DATPHONG ADD NgayTraDuKien DATE NULL;
IF COL_LENGTH('dbo.DATPHONG', 'SoLuongPhongDat') IS NULL
    ALTER TABLE dbo.DATPHONG ADD SoLuongPhongDat INT NULL;
IF COL_LENGTH('dbo.DATPHONG', 'PhiNoShow') IS NULL
    ALTER TABLE dbo.DATPHONG ADD PhiNoShow DECIMAL(18,2) NULL;
IF COL_LENGTH('dbo.DATPHONG', 'NgayXuLyNoShow') IS NULL
    ALTER TABLE dbo.DATPHONG ADD NgayXuLyNoShow DATETIME2(0) NULL;
IF COL_LENGTH('dbo.DATPHONG', 'NgayTraThucTe') IS NULL
    ALTER TABLE dbo.DATPHONG ADD NgayTraThucTe DATE NULL;
GO
-- Immutable booking detail: preserve room/type/price even after releasing the calendar.
IF OBJECT_ID(N'dbo.DATPHONG_PHONG', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DATPHONG_PHONG (
        MaDatPhong VARCHAR(10) NOT NULL,
        MaPhong VARCHAR(10) NOT NULL,
        MaLoai VARCHAR(10) NOT NULL,
        TenLoai NVARCHAR(50) NOT NULL,
        DonGia DECIMAL(18,2) NOT NULL,
        SoDem INT NOT NULL,
        ThanhTien DECIMAL(18,2) NOT NULL,
        CONSTRAINT PK_DATPHONG_PHONG PRIMARY KEY (MaDatPhong, MaPhong),
        CONSTRAINT FK_DPP_Booking FOREIGN KEY (MaDatPhong) REFERENCES dbo.DATPHONG(MaDatPhong),
        CONSTRAINT FK_DPP_Phong FOREIGN KEY (MaPhong) REFERENCES dbo.PHONG(MaPhong),
        CONSTRAINT FK_DPP_Loai FOREIGN KEY (MaLoai) REFERENCES dbo.LOAIPHONG(MaLoai),
        CONSTRAINT CK_DPP_Gia CHECK (DonGia >= 0 AND ThanhTien >= 0 AND SoDem BETWEEN 1 AND 366)
    );
END;
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.PHONG_NGAY') AND name=N'IX_PHONG_NGAY_Booking')
    CREATE INDEX IX_PHONG_NGAY_Booking ON dbo.PHONG_NGAY(MaDatPhong, MaPhong, Ngay);
IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.THANHTOAN') AND name=N'IX_THANHTOAN_Booking')
    CREATE INDEX IX_THANHTOAN_Booking ON dbo.THANHTOAN(MaDatPhong) INCLUDE(SoTien, LoaiGiaoDich, NgayGD);
GO
-- Only active bookings still have a usable room schedule. Do not invent lost history.
;WITH RoomDates AS (
    SELECT MaDatPhong, MaPhong, MIN(Ngay) AS NgayNhan, MAX(Ngay) AS NgayCuoi, COUNT(*) AS SoNgay
    FROM dbo.PHONG_NGAY WHERE MaDatPhong IS NOT NULL GROUP BY MaDatPhong, MaPhong
), BookingDates AS (
    SELECT MaDatPhong, MIN(NgayNhan) AS NgayNhan, MAX(NgayCuoi) AS NgayCuoi, COUNT(*) AS SoPhong
    FROM RoomDates GROUP BY MaDatPhong
    HAVING MIN(NgayNhan) = MAX(NgayNhan) AND MIN(NgayCuoi) = MAX(NgayCuoi)
       AND MAX(CASE WHEN SoNgay <> DATEDIFF(DAY, NgayNhan, NgayCuoi) + 1 THEN 1 ELSE 0 END) = 0
)
UPDATE dp
SET NgayNhanDuKien = COALESCE(dp.NgayNhanDuKien, d.NgayNhan),
    NgayTraDuKien = COALESCE(dp.NgayTraDuKien, DATEADD(DAY, 1, d.NgayCuoi)),
    SoLuongPhongDat = COALESCE(dp.SoLuongPhongDat, d.SoPhong)
FROM dbo.DATPHONG dp JOIN BookingDates d ON d.MaDatPhong = dp.MaDatPhong
WHERE dp.TrangThai IN (N'Đã đặt', N'Đang ở');
GO
