using HotelDesk.Data;
using HotelDesk.Models;
using System.Data;
using System.ComponentModel.DataAnnotations;
using Microsoft.Data.SqlClient;
namespace HotelDesk.Services;

public sealed record ViewDefinition(string Key, string Title);
public sealed class HotelService(HotelDb db)
{
    public static IReadOnlyList<ViewDefinition> Views { get; } = [
        new("bookings","Booking & công nợ"), new("arrivals","Chờ nhận phòng"),
        new("stays","Khách đang lưu trú"), new("rooms","Tra cứu phòng"),
        new("giam-sat-tt", "Giám sát trạng thái booking (Realtime)"),
        new("booking","Đặt phòng mới"), new("room-management","Loại phòng & giá"),
        new("calendar","Lịch phòng"), new("transactions","Lịch sử giao dịch"),
        new("revenue","Giá trị booking theo loại")
    ];
  
    public Task<TableData> ViewAsync(string key, CancellationToken ct = default, DateTime? from = null, DateTime? to = null)
    {
        if (key is "booking" or "room-management") return Task.FromResult(TableData.Empty);
        if (key == "rooms") return SearchRoomsAsync(from ?? DateTime.Today, to ?? DateTime.Today.AddDays(1), ct);
        if (key == "giam-sat-tt") 
            return db.QueryAsync("SELECT * FROM dbo.vw_GiamSat_TrangThaiDatPhong ORDER BY MaDatPhong DESC;", cancellation: ct);
        if (key == "calendar")
        {
            var range = new CalendarRange { From = from?.Date ?? DateTime.Today, To = to?.Date ?? DateTime.Today.AddDays(6) };
            Validator.ValidateObject(range, new ValidationContext(range), validateAllProperties: true);

            // sử dụng vw_GiamSat_LichPhong
            const string calendarSql = """
                SELECT TOP (500) * FROM dbo.vw_GiamSat_LichPhong
                WHERE Ngay >= @FromDate AND Ngay <= @ToDate
                ORDER BY Ngay, MaPhong;
                """;
            return db.QueryAsync(calendarSql, [
                new SqlParameter("@FromDate", SqlDbType.Date) { Value = range.From },
                new SqlParameter("@ToDate", SqlDbType.Date) { Value = range.To }
            ], ct);
        }

        //sử dụng các view khác như vw_QuyetToanBooking, vw_BookingChoNhanPhong, vw_KhachDangLuuTru, vw_LichSuGiaoDichBooking, vw_BaoCao_DoanhThu_LoaiPhong
        var sql = key switch
        {
            "bookings" => "SELECT TOP (500) * FROM dbo.vw_QuyetToanBooking ORDER BY MaDatPhong DESC;",
            "arrivals" => "SELECT TOP (500) * FROM dbo.vw_BookingChoNhanPhong ORDER BY MaDatPhong DESC;",
            "stays" => "SELECT TOP (500) * FROM dbo.vw_KhachDangLuuTru ORDER BY MaDatPhong, MaPhong;",
            "transactions" => "SELECT TOP (500) * FROM dbo.vw_LichSuGiaoDichBooking ORDER BY NgayGD DESC, MaGD;",
            "status" => "SELECT TOP (500) * FROM dbo.vw_QuyetToanBooking ORDER BY MaDatPhong DESC;",
            "revenue" => "SELECT TOP (500) * FROM dbo.vw_BaoCao_DoanhThu_LoaiPhong ORDER BY MaLoai;",
            _ => throw new ValidationException("View không tồn tại.")
        };
        return db.QueryAsync(sql, cancellation: ct);
    }
    public async Task<(TableData Customers, TableData Staff, TableData Rooms, TableData RoomTypes)> CatalogAsync()
    {
        var customers = db.QueryAsync("SELECT MaKH, HoTen FROM dbo.KHACHHANG ORDER BY MaKH;");
        var staff = db.QueryAsync("SELECT MaNV, HoTen FROM dbo.NHANVIEN ORDER BY MaNV;");
        var rooms = db.QueryAsync("SELECT MaPhong, SoPhong FROM dbo.PHONG ORDER BY MaPhong;");
        var roomTypes = db.QueryAsync("SELECT MaLoai, TenLoai, GiaCoBan FROM dbo.LOAIPHONG ORDER BY MaLoai;");
        await Task.WhenAll(customers, staff, rooms, roomTypes);
        return (await customers, await staff, await rooms, await roomTypes);
    }

    // sử dụng sp_ThemLoaiPhong và sp_CapNhatGiaLoaiPhong để thêm loại phòng mới và cập nhật giá cơ bản của loại phòng
    public Task<TableData> AddRoomTypeAsync(RoomTypeChange model)
    {
        Validator.ValidateObject(model, new ValidationContext(model), validateAllProperties: true);
        const string sql = "EXEC dbo.sp_ThemLoaiPhong @MaLoai = @RoomTypeId, @TenLoai = @RoomTypeName, @GiaCoBan = @BasePrice;";
        return db.QueryAsync(sql, [
            new SqlParameter("@RoomTypeId", SqlDbType.VarChar, 10) { Value = model.RoomTypeId.Trim() },
            new SqlParameter("@RoomTypeName", SqlDbType.NVarChar, 50) { Value = model.RoomTypeName.Trim() },
            new SqlParameter("@BasePrice", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = model.BasePrice }
        ]);
    }
    public Task<TableData> UpdateRoomTypePriceAsync(string roomTypeId, decimal basePrice)
    {
        if (string.IsNullOrWhiteSpace(roomTypeId) || basePrice < 0 || decimal.Round(basePrice, 2) != basePrice)
            throw new ValidationException("Chọn loại phòng và nhập giá không âm, tối đa 2 chữ số thập phân.");
        const string sql = "EXEC dbo.sp_CapNhatGiaLoaiPhong @MaLoai = @RoomTypeId, @GiaCoBan = @BasePrice;";
        return db.QueryAsync(sql, [
            new SqlParameter("@RoomTypeId", SqlDbType.VarChar, 10) { Value = roomTypeId },
            new SqlParameter("@BasePrice", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = basePrice }
        ]);
    }
    

    // sử dụng view tra cứu phòng
    public Task<TableData> SearchRoomsAsync(DateTime arrival, DateTime departure, CancellationToken ct = default)
    {
        if (arrival.Date < DateTime.Today || departure.Date <= arrival.Date || (departure.Date - arrival.Date).Days > 366)
            throw new ValidationException("Ngày nhận từ hôm nay; ngày trả sau ngày nhận, tối đa 366 đêm.");
        const string sql = """
            SELECT TOP (500) MaPhong, SoPhong, MaLoai, TenLoai, GiaCoBan,
                   @Arrival AS NgayNhan, @Departure AS NgayTra,
                   CAST(GiaCoBan * DATEDIFF(DAY, @Arrival, @Departure) AS decimal(18,2)) AS TienPhongDuKien
            FROM dbo.vw_TraCuuPhong
            WHERE Ngay >= @Arrival AND Ngay < @Departure
            GROUP BY MaPhong, SoPhong, MaLoai, TenLoai, GiaCoBan
            HAVING COUNT_BIG(*) = DATEDIFF(DAY, @Arrival, @Departure)
               AND COUNT(MaDatPhong) = 0
            ORDER BY MaPhong;
            """;
        return db.QueryAsync(sql, [
            new SqlParameter("@Arrival", SqlDbType.Date) { Value = arrival.Date },
            new SqlParameter("@Departure", SqlDbType.Date) { Value = departure.Date }
        ], ct);
    }

    // Refactor Dirty Read: Gọi SP sp_TraCuuPhongTrong_DirtyRead thay cho SQL thô
    public Task<TableData> SearchRoomsDemoAsync(
        DateTime arrival,
        DateTime departure,
        CancellationToken ct = default)
    {
        if (arrival.Date < DateTime.Today ||
            departure.Date <= arrival.Date ||
            (departure.Date - arrival.Date).Days > 366)
        {
            throw new ValidationException(
                "Ngày nhận từ hôm nay; ngày trả sau ngày nhận, tối đa 366 đêm.");
        }

        return db.QueryAsync(
            "EXEC dbo.sp_TraCuuPhongTrong_DirtyRead @NgayNhan = @Arrival, @NgayTra = @Departure;",
            [
                new SqlParameter("@Arrival", SqlDbType.Date) { Value = arrival.Date },
                new SqlParameter("@Departure", SqlDbType.Date) { Value = departure.Date }
            ],
            ct);
    }

    public async Task<TableData> CreateAsync(NewBooking model)
    {
        BookingValidation.Validate(model);
        if (string.IsNullOrWhiteSpace(model.CustomerId))
        {
            var customer = await db.QueryAsync("EXEC dbo.sp_TaoKhachHangTuThongTin @HoTen = @Name, @SDT = @Phone, @CCCD = @Identity, @Email = @Email;", [
                new SqlParameter("@Name", SqlDbType.NVarChar, 200) { Value = model.CustomerName.Trim() },
                new SqlParameter("@Phone", SqlDbType.VarChar, 15) { Value = model.CustomerPhone.Trim() },
                new SqlParameter("@Identity", SqlDbType.VarChar, 20) { Value = model.CustomerIdentity.Trim() },
                new SqlParameter("@Email", SqlDbType.VarChar, 100) { Value = string.IsNullOrWhiteSpace(model.CustomerEmail) ? DBNull.Value : model.CustomerEmail.Trim() }
            ]);
            model.CustomerId = customer.Rows.FirstOrDefault()?.GetValueOrDefault("MaKH")?.ToString()
                ?? throw new InvalidOperationException("Không tạo được khách hàng.");
        }
        const string sql = """
            EXEC dbo.sp_DatPhong
                @MaDatPhong = @BookingId,
                @MaKH = @CustomerId,
                @MaNV = @StaffId,
                @NgayNhan = @ArrivalDate,
                @NgayTra = @DepartureDate,
                @DanhSachPhong = @Rooms;
            """;
        using var rooms = new DataTable();
        rooms.Columns.Add("MaPhong", typeof(string));
        foreach (var room in model.RoomIds) rooms.Rows.Add(room);
        return await db.QueryAsync(sql, [
            new SqlParameter("@BookingId", SqlDbType.VarChar, 10) { Value = string.IsNullOrWhiteSpace(model.BookingId) ? DBNull.Value : model.BookingId },
            new SqlParameter("@CustomerId", SqlDbType.VarChar, 10) { Value = model.CustomerId },
            new SqlParameter("@StaffId", SqlDbType.VarChar, 10) { Value = model.StaffId },
            new SqlParameter("@ArrivalDate", SqlDbType.Date) { Value = model.ArrivalDate.Date },
            new SqlParameter("@DepartureDate", SqlDbType.Date) { Value = model.DepartureDate.Date },
            new SqlParameter("@Rooms", SqlDbType.Structured) { TypeName = "dbo.DanhSachPhongDat", Value = rooms }
        ]);
    }

    public async Task<TableData> CreateDeadlockAsync(NewBooking model)
    {
        BookingValidation.Validate(model);

        if (model.RoomIds is null || model.RoomIds.Length < 2)
        {
            throw new ValidationException(
                "Demo deadlock cần chọn ít nhất 2 phòng.");
        }

        if (string.IsNullOrWhiteSpace(model.CustomerId))
        {
            var customer = await db.QueryAsync(
                """
                EXEC dbo.sp_TaoKhachHangTuThongTin
                    @HoTen = @Name,
                    @SDT = @Phone,
                    @CCCD = @Identity,
                    @Email = @Email;
                """,
                [
                    new SqlParameter("@Name", SqlDbType.NVarChar, 200) { Value = model.CustomerName.Trim() },
                    new SqlParameter("@Phone", SqlDbType.VarChar, 15) { Value = model.CustomerPhone.Trim() },
                    new SqlParameter("@Identity", SqlDbType.VarChar, 20) { Value = model.CustomerIdentity.Trim() },
                    new SqlParameter("@Email", SqlDbType.VarChar, 100) { Value = string.IsNullOrWhiteSpace(model.CustomerEmail) ? DBNull.Value : model.CustomerEmail.Trim() }
                ]);

            model.CustomerId = customer.Rows.FirstOrDefault()?.GetValueOrDefault("MaKH")?.ToString()
                ?? throw new InvalidOperationException("Không tạo được khách hàng.");
        }

        using var rooms = new DataTable();
        rooms.Columns.Add("ThuTu", typeof(int));
        rooms.Columns.Add("MaPhong", typeof(string));

        for (var i = 0; i < model.RoomIds.Length; i++)
        {
            rooms.Rows.Add(i + 1, model.RoomIds[i]);
        }

        const string sql = """
            EXEC dbo.sp_DatPhong_Deadlock
                @MaDatPhong = @BookingId,
                @MaKH = @CustomerId,
                @MaNV = @StaffId,
                @NgayNhan = @ArrivalDate,
                @NgayTra = @DepartureDate,
                @DanhSachPhong = @Rooms;
            """;

        return await db.QueryAsync(
            sql,
            [
                new SqlParameter("@BookingId", SqlDbType.VarChar, 10) { Value = string.IsNullOrWhiteSpace(model.BookingId) ? DBNull.Value : model.BookingId },
                new SqlParameter("@CustomerId", SqlDbType.VarChar, 10) { Value = model.CustomerId },
                new SqlParameter("@StaffId", SqlDbType.VarChar, 10) { Value = model.StaffId },
                new SqlParameter("@ArrivalDate", SqlDbType.Date) { Value = model.ArrivalDate.Date },
                new SqlParameter("@DepartureDate", SqlDbType.Date) { Value = model.DepartureDate.Date },
                new SqlParameter("@Rooms", SqlDbType.Structured) { TypeName = "dbo.DanhSachPhongDatCoThuTu", Value = rooms }
            ]);
    }

    // Hỗ trợ chọn SP bản Lỗi (sp_DatPhong_KhongBaoVe) hoặc bản Fix (sp_DatPhong_BaoVe)
    public async Task<TableData> CreateUnsafeAsync(NewBooking model, bool isFixed = false)
    {
        BookingValidation.Validate(model);
        if (string.IsNullOrWhiteSpace(model.CustomerId))
        {
            var customer = await db.QueryAsync("EXEC dbo.sp_TaoKhachHangTuThongTin @HoTen = @Name, @SDT = @Phone, @CCCD = @Identity, @Email = @Email;", [
                new SqlParameter("@Name", SqlDbType.NVarChar, 200) { Value = model.CustomerName.Trim() },
                new SqlParameter("@Phone", SqlDbType.VarChar, 15) { Value = model.CustomerPhone.Trim() },
                new SqlParameter("@Identity", SqlDbType.VarChar, 20) { Value = model.CustomerIdentity.Trim() },
                new SqlParameter("@Email", SqlDbType.VarChar, 100) { Value = string.IsNullOrWhiteSpace(model.CustomerEmail) ? DBNull.Value : model.CustomerEmail.Trim() }
            ]);
            model.CustomerId = customer.Rows.FirstOrDefault()?.GetValueOrDefault("MaKH")?.ToString()
                ?? throw new InvalidOperationException("Không tạo được khách hàng.");
        }

        string spName = isFixed ? "dbo.sp_DatPhong_BaoVe" : "dbo.sp_DatPhong_KhongBaoVe";
        string sql = $"""
            EXEC {spName}
                @MaDatPhong = @BookingId,
                @MaKH = @CustomerId,
                @MaNV = @StaffId,
                @NgayNhan = @ArrivalDate,
                @NgayTra = @DepartureDate,
                @DanhSachPhong = @Rooms;
            """;
        using var rooms = new DataTable();
        rooms.Columns.Add("MaPhong", typeof(string));
        foreach (var room in model.RoomIds) rooms.Rows.Add(room);
        return await db.QueryAsync(sql, [
            new SqlParameter("@BookingId", SqlDbType.VarChar, 10) { Value = string.IsNullOrWhiteSpace(model.BookingId) ? DBNull.Value : model.BookingId },
            new SqlParameter("@CustomerId", SqlDbType.VarChar, 10) { Value = model.CustomerId },
            new SqlParameter("@StaffId", SqlDbType.VarChar, 10) { Value = model.StaffId },
            new SqlParameter("@ArrivalDate", SqlDbType.Date) { Value = model.ArrivalDate.Date },
            new SqlParameter("@DepartureDate", SqlDbType.Date) { Value = model.DepartureDate.Date },
            new SqlParameter("@Rooms", SqlDbType.Structured) { TypeName = "dbo.DanhSachPhongDat", Value = rooms }
        ]);
    }

    public Task<TableData> OperateAsync(BookingOperation model)
    {
        BookingValidation.Validate(model);
        return model.Action switch
        {
            BookingAction.CheckIn => NhanPhongAsync(model),
            BookingAction.Deposit => DatCocAsync(model),
            BookingAction.CheckOut => TraPhongAsync(model),
            BookingAction.CheckOutDemo => TraPhongDemoAsync(model),
            BookingAction.Cancel => HuyBookingAsync(model),
            BookingAction.NoShow => NoShowAsync(model),
            _ => throw new ValidationException("Nghiệp vụ không hợp lệ.")
        };
    }
    private Task<TableData> NoShowAsync(BookingOperation model)
    {
        const string sql = """
            EXEC dbo.sp_NoShow_NhaPhong @MaDatPhong = @BookingId, @Version = @Version,
                @PhiPhat = @Fee, @SoTienHoanTra = @Amount, @MaGDHoanTien = @PaymentId;
            """;
        return db.QueryAsync(sql, [
            new SqlParameter("@BookingId", SqlDbType.VarChar, 10) { Value = model.BookingId },
            new SqlParameter("@Version", SqlDbType.Int) { Value = model.Version },
            new SqlParameter("@Fee", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = model.NoShowFee },
            new SqlParameter("@Amount", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = model.Amount },
            new SqlParameter("@PaymentId", SqlDbType.VarChar, 10) { Value = (object?)model.PaymentId ?? DBNull.Value }
        ]);
    }

    private Task<TableData> NhanPhongAsync(BookingOperation model)
    {
        const string sql = """
            EXEC dbo.sp_NhanPhong
                @MaDatPhong = @BookingId,
                @Version = @Version;
            """;
        return db.QueryAsync(sql, [
            new SqlParameter("@BookingId", SqlDbType.VarChar, 10) { Value = model.BookingId },
            new SqlParameter("@Version", SqlDbType.Int) { Value = model.Version }
        ]);
    }
    private Task<TableData> DatCocAsync(BookingOperation model)
    {
        const string sql = """
            EXEC dbo.sp_DatCoc
                @MaDatPhong = @BookingId,
                @Version = @Version,
                @SoTien = @Amount,
                @MaGD = @PaymentId;
            """;
        return db.QueryAsync(sql, [
            new SqlParameter("@BookingId", SqlDbType.VarChar, 10) { Value = model.BookingId },
            new SqlParameter("@Version", SqlDbType.Int) { Value = model.Version },
            new SqlParameter("@Amount", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = model.Amount },
            new SqlParameter("@PaymentId", SqlDbType.VarChar, 10) { Value = (object?)model.PaymentId ?? DBNull.Value }
        ]);
    }
    private Task<TableData> TraPhongAsync(BookingOperation model)
    {
        const string sql = """
            EXEC dbo.sp_TraPhong
                @MaDatPhong = @BookingId,
                @Version = @Version,
                @SoTienThanhToan = @Amount,
                @MaGD = @PaymentId;
            """;
        return db.QueryAsync(sql, [
            new SqlParameter("@BookingId", SqlDbType.VarChar, 10) { Value = model.BookingId },
            new SqlParameter("@Version", SqlDbType.Int) { Value = model.Version },
            new SqlParameter("@Amount", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = model.Amount },
            new SqlParameter("@PaymentId", SqlDbType.VarChar, 10) { Value = (object?)model.PaymentId ?? DBNull.Value }
        ]);
    }
    private Task<TableData> TraPhongDemoAsync(BookingOperation model)
    {
        const string sql = """
            EXEC dbo.sp_TraPhongDemo
                @MaDatPhong = @BookingId,
                @Version = @Version,
                @SoTienThanhToan = @Amount,
                @MaGD = @PaymentId;
            """;
        return db.QueryAsync(sql, [
            new SqlParameter("@BookingId", SqlDbType.VarChar, 10) { Value = model.BookingId },
            new SqlParameter("@Version", SqlDbType.Int) { Value = model.Version },
            new SqlParameter("@Amount", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = model.Amount },
            new SqlParameter("@PaymentId", SqlDbType.VarChar, 10) { Value = (object?)model.PaymentId ?? DBNull.Value }
        ]);
    }

    private Task<TableData> HuyBookingAsync(BookingOperation model)
    {
        const string sql = """
            EXEC dbo.sp_HuyBooking
                @MaDatPhong = @BookingId,
                @Version = @Version,
                @SoTienHoanTra = @Amount,
                @MaGDHoanTien = @PaymentId;
            """;
        return db.QueryAsync(sql, [
            new SqlParameter("@BookingId", SqlDbType.VarChar, 10) { Value = model.BookingId },
            new SqlParameter("@Version", SqlDbType.Int) { Value = model.Version },
            new SqlParameter("@Amount", SqlDbType.Decimal) { Precision = 18, Scale = 2, Value = model.Amount },
            new SqlParameter("@PaymentId", SqlDbType.VarChar, 10) { Value = (object?)model.PaymentId ?? DBNull.Value }
        ]);
    }

    public Task<TableData> ResetConcurrencyDemoAsync(CancellationToken ct = default) =>
        db.QueryAsync("EXEC dbo.sp_Demo_XungDot_Reset;", cancellation: ct);

    public Task<TableData> NonRepeatReadSessionAAsync(bool fixedVersion, CancellationToken ct = default) =>
        db.QueryAsync(fixedVersion
            ? "EXEC dbo.sp_Demo_NonRepeatRead_SessionA_Fixed;"
            : "EXEC dbo.sp_Demo_NonRepeatRead_SessionA;", cancellation: ct);

    public Task<TableData> NonRepeatReadSessionBAsync(CancellationToken ct = default) =>
        db.QueryAsync("EXEC dbo.sp_Demo_NonRepeatRead_SessionB;", cancellation: ct);

    public Task<TableData> PhantomReadSessionAAsync(bool fixedVersion, CancellationToken ct = default) =>
        db.QueryAsync(fixedVersion
            ? "EXEC dbo.sp_Demo_PhantomRead_SessionA_Fixed;"
            : "EXEC dbo.sp_Demo_PhantomRead_SessionA;", cancellation: ct);

    public Task<TableData> PhantomReadSessionBAsync(CancellationToken ct = default) =>
        db.QueryAsync("EXEC dbo.sp_Demo_PhantomRead_SessionB;", cancellation: ct);
}

public static class SqlFeedback
{
    public static (int? Code, string Message) Explain(Exception error)
    {
        if (error is SqlException sql)
        {
            var number = sql.Errors.Cast<SqlError>().Select(e => e.Number)
                .FirstOrDefault(n => n is 1205 or 1222 or 50006 or 50109 or 50308 or 50211 or 51505 or 51511);
            if (number == 0) number = sql.Number;
            return (number, number switch
            {
                1205 => "Deadlock: SQL Server chọn phiên này làm victim và rollback transaction.",
                1222 => "Hết thời gian chờ khóa (1222). Đây không phải bằng chứng đã xảy ra deadlock.",
                -2 => "Hết thời gian thực thi lệnh. Tải lại dữ liệu để kiểm tra trạng thái trước khi thử lại; không tự động gửi lại giao dịch.",
                50006 or 50109 or 50308 or 50211 or 51505 or 51511 => "Booking hoặc số dư đã thay đổi. Bấm Tải lại dữ liệu, chọn lại booking và kiểm tra số tiền trước khi xác nhận lại.",
                >= 50000 => sql.Message,
                2601 or 2627 => "Mã booking hoặc giao dịch đã tồn tại. Kiểm tra dữ liệu rồi dùng mã mới.",
                208 or 2812 => "Thiếu bảng, view hoặc SP. Chạy bộ SQL trong thư mục sql theo README.",
                _ => $"Không thực hiện được SQL (mã {number}). Kiểm tra kết nối, quyền truy cập và database."
            });
        }
        if (error is ValidationException or InvalidOperationException) return (null, error.Message);
        if (error is OperationCanceledException) return (null, "Thao tác bị hủy hoặc quá thời gian. Kiểm tra dữ liệu trước khi thử lại.");
        return (null, "Không hoàn tất thao tác. Xem log ứng dụng để kiểm tra lỗi.");
    }
}