USE QL_KhachSan;
GO

CREATE OR ALTER PROCEDURE dbo.sp_HuyBooking
    @MaDatPhong VARCHAR(MAX),
    @Version INT,
    @SoTienHoanTra DECIMAL(18, 2) = 0,
    @MaGDHoanTien VARCHAR(MAX) = NULL,
    @MaKHThucHien VARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @@TRANCOUNT <> 0
        THROW 50201, N'Procedure phải được gọi ngoài transaction đang mở.', 1;

    SET XACT_ABORT ON;
    IF @MaKHThucHien IS NOT NULL AND LTRIM(RTRIM(@MaKHThucHien))=''
        THROW 50207, N'Mã khách thực hiện không được là chuỗi trống.', 1;
    SET @MaDatPhong = NULLIF(LTRIM(RTRIM(@MaDatPhong)), '');
    SET @MaGDHoanTien = NULLIF(LTRIM(RTRIM(@MaGDHoanTien)), '');
    SET @MaKHThucHien = NULLIF(LTRIM(RTRIM(@MaKHThucHien)), '');
    IF @MaDatPhong IS NOT NULL AND (DATALENGTH(@MaDatPhong) > 10 OR @MaDatPhong COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%')
        THROW 51601, N'Mã chỉ được chứa 1–10 ký tự chữ, số, dấu - hoặc _.', 1;
    IF @MaGDHoanTien IS NOT NULL AND (DATALENGTH(@MaGDHoanTien) > 10 OR @MaGDHoanTien COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%')
        THROW 51601, N'Mã chỉ được chứa 1–10 ký tự chữ, số, dấu - hoặc _.', 1;
    IF @MaKHThucHien IS NOT NULL AND (DATALENGTH(@MaKHThucHien) > 10 OR @MaKHThucHien COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%')
        THROW 51601, N'Mã chỉ được chứa 1–10 ký tự chữ, số, dấu - hoặc _.', 1;

    IF @MaDatPhong IS NULL OR LTRIM(RTRIM(@MaDatPhong)) = ''
        THROW 50202, N'Mã đặt phòng không được để trống.', 1;

    IF @Version IS NULL OR @Version < 1
        THROW 50203, N'Version phải là số nguyên dương.', 1;

    IF @SoTienHoanTra IS NULL OR @SoTienHoanTra < 0
        THROW 50204, N'Số tiền hoàn phải lớn hơn hoặc bằng 0.', 1;

    SET @MaGDHoanTien = NULLIF(LTRIM(RTRIM(@MaGDHoanTien)), '');

    IF @SoTienHoanTra = 0 AND @MaGDHoanTien IS NOT NULL
        THROW 50206, N'Không truyền mã giao dịch khi không hoàn thêm tiền.', 1;

    IF @MaKHThucHien IS NOT NULL AND LTRIM(RTRIM(@MaKHThucHien)) = ''
        THROW 50207, N'Mã khách thực hiện không được là chuỗi trống.', 1;

    DECLARE @TrangThai NVARCHAR(50);
    DECLARE @VersionHienTai INT;
    DECLARE @MaKHBooking VARCHAR(10);
    DECLARE @TongTienGoc DECIMAL(18, 2);
    DECLARE @DaThuRong DECIMAL(28, 2);
    DECLARE @CoGiaoDichSai INT;
    DECLARE @SoDemPhongGiaiPhong INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        SELECT
            @TrangThai = dp.TrangThai,
            @VersionHienTai = dp.Version,
            @MaKHBooking = dp.MaKH,
            @TongTienGoc = dp.TongTien
        FROM dbo.DATPHONG AS dp WITH (UPDLOCK, HOLDLOCK)
        WHERE dp.MaDatPhong = @MaDatPhong;

        IF @VersionHienTai IS NULL
            THROW 50208, N'Booking không tồn tại hoặc thiếu Version.', 1;

        IF @MaKHThucHien IS NOT NULL
           AND (@MaKHBooking IS NULL OR @MaKHThucHien <> @MaKHBooking)
            THROW 50209, N'Khách hàng chỉ được hủy booking của mình.', 1;

        IF @VersionHienTai <> @Version
            THROW 50211, N'Booking đã thay đổi. Vui lòng tải lại dữ liệu.', 1;

        IF @TrangThai IS NULL OR @TrangThai <> N'Đã đặt'
            THROW 50210, N'Chỉ được hủy booking có trạng thái Đã đặt.', 1;


        UPDATE dbo.PHONG_NGAY
        SET MaDatPhong = NULL
        WHERE MaDatPhong = @MaDatPhong;

        SET @SoDemPhongGiaiPhong = @@ROWCOUNT;

        SELECT
            @DaThuRong = COALESCE(SUM(
                CASE
                    WHEN tt.LoaiGiaoDich IN (N'Đặt cọc', N'Thanh toán')
                        THEN tt.SoTien
                    WHEN tt.LoaiGiaoDich = N'Hoàn tiền'
                        THEN -tt.SoTien
                    ELSE 0
                END
            ), 0),
            @CoGiaoDichSai = COALESCE(MAX(
                CASE
                    WHEN tt.LoaiGiaoDich IS NULL
                      OR tt.LoaiGiaoDich NOT IN
                         (N'Đặt cọc', N'Thanh toán', N'Hoàn tiền')
                      OR tt.SoTien IS NULL OR tt.SoTien <= 0
                        THEN 1
                    ELSE 0
                END
            ), 0)
        FROM dbo.THANHTOAN AS tt WITH (UPDLOCK, HOLDLOCK)
        WHERE tt.MaDatPhong = @MaDatPhong;

        IF @CoGiaoDichSai = 1
            THROW 50212, N'Có giao dịch sai số tiền hoặc loại giao dịch chưa được hỗ trợ.', 1;

        IF @DaThuRong < 0
            THROW 50213, N'Tổng tiền hoàn vượt tiền đã thu. Cần kiểm tra giao dịch.', 1;

        IF @SoTienHoanTra <> @DaThuRong
            THROW 50214, N'Khoản hoàn xác nhận phải bằng tiền đã thu ròng. Hãy tải lại số dư.', 1;

        IF @SoTienHoanTra > 0
        BEGIN
            DECLARE @MaGDCuSo VARCHAR(30) = CONCAT(@MaDatPhong, '_HT');
            DECLARE @SoThuTuGiaoDich INT = 1;
            SET @MaGDHoanTien = @MaGDCuSo;
            WHILE EXISTS (SELECT 1 FROM dbo.THANHTOAN WHERE MaGD = @MaGDHoanTien)
            BEGIN
                SET @SoThuTuGiaoDich += 1;
                SET @MaGDHoanTien = CONCAT(@MaGDCuSo, RIGHT(CONCAT('0', @SoThuTuGiaoDich), 2));
            END;

            INSERT INTO dbo.THANHTOAN
                (MaGD, MaDatPhong, SoTien, LoaiGiaoDich, NgayGD)
            VALUES
                (@MaGDHoanTien, @MaDatPhong, @SoTienHoanTra,
                 N'Hoàn tiền', GETDATE());
        END;

        UPDATE dbo.DATPHONG
        SET TrangThai = N'Đã hủy',
            Version = Version + 1
        WHERE MaDatPhong = @MaDatPhong
          AND TrangThai = N'Đã đặt'
          AND Version = @Version;

        IF @@ROWCOUNT <> 1
            THROW 50215, N'Không thể hoàn tất hủy booking. Vui lòng tải lại dữ liệu.', 1;

        SELECT @VersionHienTai = dp.Version
        FROM dbo.DATPHONG AS dp
        WHERE dp.MaDatPhong = @MaDatPhong;

        COMMIT TRANSACTION;

        SELECT
            @MaDatPhong AS MaDatPhong,
            N'Đã hủy' AS TrangThai,
            @TongTienGoc AS TongTienBookingGoc,
            @SoTienHoanTra AS HoanTienLanNay,
            CAST(0 AS DECIMAL(18, 2)) AS ConPhaiTra,
            @SoDemPhongGiaiPhong AS SoDemPhongGiaiPhong,
            @MaGDHoanTien AS MaGiaoDichMoi,
            @VersionHienTai AS Version,
            N'Hủy booking thành công.' AS ThongBao;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
