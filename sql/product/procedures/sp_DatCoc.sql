USE QL_KhachSan;
GO

CREATE OR ALTER PROCEDURE dbo.sp_DatCoc
    @MaDatPhong VARCHAR(MAX),
    @Version INT,
    @MaGD VARCHAR(MAX),
    @SoTien DECIMAL(18, 2)
AS
BEGIN
    SET NOCOUNT ON;

    IF @@TRANCOUNT <> 0
        THROW 50301, N'Procedure phải được gọi ngoài transaction đang mở.', 1;

    SET XACT_ABORT ON;
    SET @MaDatPhong = NULLIF(LTRIM(RTRIM(@MaDatPhong)), '');
    SET @MaGD = NULLIF(LTRIM(RTRIM(@MaGD)), '');
    IF @MaDatPhong IS NOT NULL AND (DATALENGTH(@MaDatPhong) > 10 OR @MaDatPhong COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%')
        THROW 51601, N'Mã chỉ được chứa 1–10 ký tự chữ, số, dấu - hoặc _.', 1;
    IF @MaGD IS NOT NULL AND (DATALENGTH(@MaGD) > 10 OR @MaGD COLLATE Latin1_General_100_BIN2 LIKE '%[^A-Za-z0-9_-]%')
        THROW 51601, N'Mã chỉ được chứa 1–10 ký tự chữ, số, dấu - hoặc _.', 1;

    IF @MaDatPhong IS NULL OR LTRIM(RTRIM(@MaDatPhong)) = ''
        THROW 50302, N'Mã đặt phòng không được để trống.', 1;

    IF @Version IS NULL OR @Version < 1
        THROW 50303, N'Version phải là số nguyên dương.', 1;

    SET @MaGD = NULLIF(LTRIM(RTRIM(@MaGD)), '');



    IF @SoTien IS NULL OR @SoTien <= 0
        THROW 50305, N'Số tiền đặt cọc phải lớn hơn 0.', 1;

    DECLARE @TrangThai NVARCHAR(50);
    DECLARE @VersionHienTai INT;
    DECLARE @TongTien DECIMAL(18, 2);
    DECLARE @DaThuRong DECIMAL(28, 2);
    DECLARE @ConPhaiTra DECIMAL(28, 2);
    DECLARE @CoGiaoDichSai INT;
    DECLARE @NgayGD DATETIME;

    BEGIN TRY
        BEGIN TRANSACTION;


        SELECT
            @TrangThai = dp.TrangThai,
            @VersionHienTai = dp.Version,
            @TongTien = dp.TongTien
        FROM dbo.DATPHONG AS dp WITH (UPDLOCK, HOLDLOCK)
        WHERE dp.MaDatPhong = @MaDatPhong;

        IF @VersionHienTai IS NULL
            THROW 50306, N'Booking không tồn tại hoặc thiếu Version.', 1;

        IF @VersionHienTai <> @Version
            THROW 50308, N'Booking đã thay đổi. Vui lòng tải lại dữ liệu.', 1;

        IF @TrangThai IS NULL OR @TrangThai <> N'Đã đặt'
            THROW 50307, N'Chỉ được đặt cọc cho booking có trạng thái Đã đặt.', 1;

        IF @TongTien IS NULL OR @TongTien < 0
            THROW 50309, N'Booking chưa có tổng tiền hợp lệ.', 1;


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
            THROW 50310, N'Có giao dịch sai số tiền hoặc loại giao dịch chưa được hỗ trợ.', 1;

        IF @DaThuRong < 0
            THROW 50311, N'Tổng tiền hoàn vượt tiền đã thu. Cần kiểm tra giao dịch.', 1;

        SET @ConPhaiTra = @TongTien - @DaThuRong;

        IF @ConPhaiTra <= 0
            THROW 50312, N'Booking đã thanh toán đủ hoặc đang nộp dư; không nhận thêm cọc.', 1;

        IF @SoTien > @ConPhaiTra
            THROW 50313, N'Tiền đặt cọc vượt số còn phải trả. Vui lòng tải lại số dư.', 1;

        DECLARE @MaGDCuSo VARCHAR(30) = CONCAT(@MaDatPhong, '_DC');
        DECLARE @SoThuTuGiaoDich INT = 1;
        SET @MaGD = @MaGDCuSo;
        WHILE EXISTS (SELECT 1 FROM dbo.THANHTOAN WHERE MaGD = @MaGD)
        BEGIN
            SET @SoThuTuGiaoDich += 1;
            SET @MaGD = CONCAT(@MaGDCuSo, RIGHT(CONCAT('0', @SoThuTuGiaoDich), 2));
        END;

        SET @NgayGD = GETDATE();

        INSERT INTO dbo.THANHTOAN
            (MaGD, MaDatPhong, SoTien, LoaiGiaoDich, NgayGD)
        VALUES
            (@MaGD, @MaDatPhong, @SoTien, N'Đặt cọc', @NgayGD);

        UPDATE dbo.DATPHONG
        SET Version = Version + 1
        WHERE MaDatPhong = @MaDatPhong
          AND TrangThai = N'Đã đặt'
          AND Version = @Version;

        IF @@ROWCOUNT <> 1
            THROW 50314, N'Không thể hoàn tất đặt cọc. Vui lòng tải lại booking.', 1;

        SELECT @VersionHienTai = dp.Version
        FROM dbo.DATPHONG AS dp
        WHERE dp.MaDatPhong = @MaDatPhong;

        COMMIT TRANSACTION;

        SELECT
            @MaDatPhong AS MaDatPhong,
            @MaGD AS MaGD,
            N'Đặt cọc' AS LoaiGiaoDich,
            @NgayGD AS NgayGD,
            @TongTien AS TongTien,
            @DaThuRong AS DaThanhToanRongTruocDo,
            @SoTien AS DatCocLanNay,
            @DaThuRong + @SoTien AS DaThanhToanRong,
            @ConPhaiTra - @SoTien AS ConPhaiTra,
            @TrangThai AS TrangThai,
            @VersionHienTai AS Version,
            N'Đặt cọc thành công.' AS ThongBao;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;
        THROW;
    END CATCH;
END;
GO
