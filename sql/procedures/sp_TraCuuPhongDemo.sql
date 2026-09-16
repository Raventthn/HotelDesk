CREATE OR ALTER PROCEDURE dbo.sp_TraCuuPhongTrong_DirtyRead
    @NgayNhan DATE,
    @NgayTra  DATE,
    @MaLoai   VARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @NgayNhan IS NULL OR @NgayTra IS NULL
        THROW 52201,
              N'Ngày nhận và ngày trả không được để trống.',
              1;

    IF @NgayTra <= @NgayNhan
        THROW 52202,
              N'Ngày trả phải sau ngày nhận.',
              1;

    DECLARE @SoDem INT =
        DATEDIFF(DAY, @NgayNhan, @NgayTra);

    ------------------------------------------------------------
    -- CỐ TÌNH cho phép Dirty Read
    ------------------------------------------------------------
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

    SELECT
        v.MaPhong,
        v.SoPhong,
        v.MaLoai,
        v.TenLoai,
        v.GiaCoBan
    FROM dbo.vw_TraCuuPhong AS v

    WHERE v.Ngay >= @NgayNhan
      AND v.Ngay < @NgayTra

      AND
      (
          @MaLoai IS NULL
          OR v.MaLoai = @MaLoai
      )

    GROUP BY
        v.MaPhong,
        v.SoPhong,
        v.MaLoai,
        v.TenLoai,
        v.GiaCoBan

    HAVING
        COUNT(*) = @SoDem

        AND SUM
        (
            CASE
                WHEN v.MaDatPhong IS NOT NULL THEN 1
                ELSE 0
            END
        ) = 0

    ORDER BY v.SoPhong;

    ------------------------------------------------------------
    -- Trả isolation level về mặc định
    ------------------------------------------------------------
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
END;
GO