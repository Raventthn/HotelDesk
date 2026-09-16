USE QL_KhachSan;
GO

/*
    DEMO DEADLOCK ĐẶT PHÒNG

    Mục đích:
    - Giữ nguyên thứ tự chọn phòng do client gửi xuống.
    - KHÔNG sắp xếp khóa theo MaPhong.
    - Khóa phòng theo ThuTu.
    - Chờ 5 giây sau khi khóa phòng đầu tiên để hai giao tác
      có đủ thời gian giữ hai phòng khác nhau và tạo circular wait.
    - Không retry khi gặp lỗi deadlock 1205.

    Ví dụ:
        Session A: P101 -> P102
        Session B: P102 -> P101

    Kết quả mong đợi:
        Một session bị SQL Server chọn làm deadlock victim (1205).
*/

-------------------------------------------------------------------------------
-- TVP dùng riêng cho demo deadlock.
-- Chỉ tạo nếu chưa tồn tại.
-------------------------------------------------------------------------------
IF TYPE_ID(N'dbo.DanhSachPhongDatCoThuTu') IS NULL
BEGIN
    EXEC(N'
        CREATE TYPE dbo.DanhSachPhongDatCoThuTu AS TABLE
        (
            ThuTu   INT         NOT NULL,
            MaPhong VARCHAR(10) NOT NULL,

            PRIMARY KEY (ThuTu),
            UNIQUE (MaPhong)
        );
    ');
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_DatPhong_Deadlock
    @MaDatPhong    VARCHAR(MAX),
    @MaKH          VARCHAR(MAX),
    @DanhSachPhong dbo.DanhSachPhongDatCoThuTu READONLY,
    @NgayNhan      DATE,
    @NgayTra       DATE,
    @MaNV          VARCHAR(MAX) = 'WEB'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ---------------------------------------------------------------------------
    -- Chuẩn hóa input
    ---------------------------------------------------------------------------
    SET @MaDatPhong = NULLIF(LTRIM(RTRIM(@MaDatPhong)), '');
    SET @MaKH        = NULLIF(LTRIM(RTRIM(@MaKH)), '');
    SET @MaNV        = NULLIF(LTRIM(RTRIM(@MaNV)), '');

    ---------------------------------------------------------------------------
    -- Validate cơ bản
    ---------------------------------------------------------------------------
    IF @MaKH IS NULL OR @MaNV IS NULL
        THROW 51701,
            N'Mã khách hàng và nhân viên không được để trống.',
            1;

    IF @NgayNhan IS NULL OR @NgayTra IS NULL
        THROW 51702,
            N'Ngày nhận và ngày trả không được để trống.',
            1;

    IF @NgayNhan < CONVERT(DATE, GETDATE())
        THROW 51703,
            N'Ngày nhận không được nằm trong quá khứ.',
            1;

    IF @NgayTra <= @NgayNhan
        THROW 51704,
            N'Ngày trả phải sau ngày nhận.',
            1;

    IF DATEDIFF(DAY, @NgayNhan, @NgayTra) > 366
        THROW 51705,
            N'Booking tối đa 366 đêm.',
            1;

    IF (SELECT COUNT(*) FROM @DanhSachPhong) < 2
        THROW 51706,
            N'Demo deadlock cần chọn ít nhất 2 phòng.',
            1;

    ---------------------------------------------------------------------------
    -- Variables
    ---------------------------------------------------------------------------
    DECLARE @SoDem INT =
        DATEDIFF(DAY, @NgayNhan, @NgayTra);

    DECLARE @SoPhong INT =
    (
        SELECT COUNT(*)
        FROM @DanhSachPhong
    );

    DECLARE @SoDongCanDat INT =
        @SoPhong * @SoDem;

    DECLARE @SoDongDaDat INT;
    DECLARE @SoPhongHopLe INT;
    DECLARE @GiaNhoNhat DECIMAL(18,2);
    DECLARE @TongTien DECIMAL(18,2);

    ---------------------------------------------------------------------------
    -- Transaction
    ---------------------------------------------------------------------------
    BEGIN TRY
        BEGIN TRAN;

        -----------------------------------------------------------------------
        -- Sinh mã booking
        -----------------------------------------------------------------------
        IF @MaDatPhong IS NULL
        BEGIN
            WHILE @MaDatPhong IS NULL
               OR EXISTS
               (
                   SELECT 1
                   FROM dbo.DATPHONG
                   WHERE MaDatPhong = @MaDatPhong
               )
            BEGIN
                SET @MaDatPhong =
                    CONCAT
                    (
                        'BK',
                        RIGHT
                        (
                            CONCAT
                            (
                                '00000000',
                                CONVERT
                                (
                                    VARCHAR(8),
                                    NEXT VALUE FOR dbo.Seq_MaDatPhong
                                )
                            ),
                            8
                        )
                    );
            END;
        END;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.DATPHONG
            WHERE MaDatPhong = @MaDatPhong
        )
            THROW 51707,
                N'Mã booking đã tồn tại.',
                1;

        -----------------------------------------------------------------------
        -- Kiểm tra khách hàng
        -----------------------------------------------------------------------
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.KHACHHANG
            WHERE MaKH = @MaKH
        )
            THROW 51708,
                N'Khách hàng không tồn tại.',
                1;

        -----------------------------------------------------------------------
        -- Kiểm tra nhân viên
        -----------------------------------------------------------------------
        IF NOT EXISTS
        (
            SELECT 1
            FROM dbo.NHANVIEN
            WHERE MaNV = @MaNV
        )
            THROW 51709,
                N'Nhân viên không tồn tại.',
                1;

        -----------------------------------------------------------------------
        -- Kiểm tra danh sách phòng + tính tổng tiền
        -----------------------------------------------------------------------
        SELECT
            @SoPhongHopLe = COUNT(*),
            @GiaNhoNhat = MIN(lp.GiaCoBan),
            @TongTien =
                CAST
                (
                    SUM(CAST(lp.GiaCoBan AS DECIMAL(28,2))) * @SoDem
                    AS DECIMAL(18,2)
                )
        FROM @DanhSachPhong ds
        INNER JOIN dbo.PHONG p
            ON p.MaPhong = ds.MaPhong
        INNER JOIN dbo.LOAIPHONG lp
            ON lp.MaLoai = p.MaLoai;

        IF @SoPhongHopLe <> @SoPhong
            THROW 51710,
                N'Có phòng không tồn tại.',
                1;

        IF @TongTien IS NULL
           OR @GiaNhoNhat IS NULL
           OR @GiaNhoNhat < 0
            THROW 51711,
                N'Giá phòng không hợp lệ.',
                1;

        -----------------------------------------------------------------------
        -- ĐIỂM CỐ TÌNH CÓ THỂ GÂY DEADLOCK
        --
        -- SP an toàn sẽ chuẩn hóa thứ tự lock, ví dụ ORDER BY MaPhong.
        -- SP demo này KHÔNG làm vậy.
        --
        -- Nó khóa theo ThuTu do client gửi xuống:
        --
        -- A: P101 -> P102
        -- B: P102 -> P101
        -----------------------------------------------------------------------
        DECLARE
            @ThuTu INT,
            @MaPhongKhoa VARCHAR(10),
            @PhongDaKhoa VARCHAR(10),
            @LanKhoa INT = 0;

        DECLARE PhongDeadlockCursor CURSOR LOCAL FAST_FORWARD
        FOR
            SELECT
                ThuTu,
                MaPhong
            FROM @DanhSachPhong
            ORDER BY ThuTu;

        OPEN PhongDeadlockCursor;

        FETCH NEXT
        FROM PhongDeadlockCursor
        INTO @ThuTu, @MaPhongKhoa;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @LanKhoa += 1;

            -- Giữ update lock đến hết transaction.
            SELECT @PhongDaKhoa = MaPhong
            FROM dbo.PHONG
                WITH (UPDLOCK, HOLDLOCK, ROWLOCK)
            WHERE MaPhong = @MaPhongKhoa;

            -- Chỉ chờ sau khi khóa phòng đầu tiên.
            -- Điều này làm deadlock dễ tái hiện khi demo.
            IF @LanKhoa = 1
            BEGIN
                WAITFOR DELAY '00:00:05';
            END;

            FETCH NEXT
            FROM PhongDeadlockCursor
            INTO @ThuTu, @MaPhongKhoa;
        END;

        CLOSE PhongDeadlockCursor;
        DEALLOCATE PhongDeadlockCursor;

        -----------------------------------------------------------------------
        -- Tạo booking
        -----------------------------------------------------------------------
        INSERT INTO dbo.DATPHONG
        (
            MaDatPhong,
            MaKH,
            MaNV,
            TongTien,
            TrangThai,
            Version,
            NgayNhanDuKien,
            NgayTraDuKien,
            SoLuongPhongDat
        )
        VALUES
        (
            @MaDatPhong,
            @MaKH,
            @MaNV,
            @TongTien,
            N'Đã đặt',
            1,
            @NgayNhan,
            @NgayTra,
            @SoPhong
        );

        -----------------------------------------------------------------------
        -- Lưu chi tiết phòng
        -----------------------------------------------------------------------
        INSERT INTO dbo.DATPHONG_PHONG
        (
            MaDatPhong,
            MaPhong,
            MaLoai,
            TenLoai,
            DonGia,
            SoDem,
            ThanhTien
        )
        SELECT
            @MaDatPhong,
            p.MaPhong,
            lp.MaLoai,
            lp.TenLoai,
            lp.GiaCoBan,
            @SoDem,
            CAST(lp.GiaCoBan * @SoDem AS DECIMAL(18,2))
        FROM @DanhSachPhong ds
        INNER JOIN dbo.PHONG p
            ON p.MaPhong = ds.MaPhong
        INNER JOIN dbo.LOAIPHONG lp
            ON lp.MaLoai = p.MaLoai;

        -----------------------------------------------------------------------
        -- Chiếm lịch phòng
        -----------------------------------------------------------------------
        UPDATE pn
        SET pn.MaDatPhong = @MaDatPhong
        FROM dbo.PHONG_NGAY pn
        INNER JOIN @DanhSachPhong ds
            ON ds.MaPhong = pn.MaPhong
        WHERE pn.Ngay >= @NgayNhan
          AND pn.Ngay < @NgayTra
          AND pn.MaDatPhong IS NULL;

        SET @SoDongDaDat = @@ROWCOUNT;

        IF @SoDongDaDat <> @SoDongCanDat
            THROW 51712,
                N'Một hoặc nhiều phòng đã được đặt hoặc chưa có đủ lịch phòng.',
                1;

        COMMIT;

        -----------------------------------------------------------------------
        -- Result
        -----------------------------------------------------------------------
        SELECT
            @MaDatPhong AS MaDatPhong,
            @MaKH AS MaKH,
            @NgayNhan AS NgayNhanDuKien,
            @NgayTra AS NgayTraDuKien,
            @SoPhong AS SoLuongPhong,
            @SoDem AS SoDem,
            @TongTien AS TongTien,
            N'Đã đặt' AS TrangThai,
            1 AS Version,
            N'Booking hoàn thành - phiên này không bị chọn làm deadlock victim.'
                AS ThongBao;
    END TRY
    BEGIN CATCH
        -- Dọn cursor nếu lỗi xảy ra khi cursor vẫn còn tồn tại.
        IF CURSOR_STATUS('local', 'PhongDeadlockCursor') > -1
            CLOSE PhongDeadlockCursor;

        IF CURSOR_STATUS('local', 'PhongDeadlockCursor') >= -1
            DEALLOCATE PhongDeadlockCursor;

        IF XACT_STATE() <> 0
            ROLLBACK;

        THROW;
    END CATCH;
END;
GO