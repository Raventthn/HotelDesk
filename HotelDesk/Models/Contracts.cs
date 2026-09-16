using System.ComponentModel.DataAnnotations;
using System.Data;
using System.Globalization;
using System.Text.RegularExpressions;

namespace HotelDesk.Models;

public sealed record TableData(IReadOnlyList<string> Columns, IReadOnlyList<Dictionary<string, object?>> Rows)
{
    public static TableData Empty { get; } = new([], []);
    public static string Text(object? value) => value switch
    {
        null => "—",
        DateTime d => d.ToString(d.TimeOfDay == TimeSpan.Zero ? "dd/MM/yyyy" : "dd/MM/yyyy HH:mm"),
        decimal d => d.ToString("N2", CultureInfo.GetCultureInfo("vi-VN")),
        bool b => b ? "Có" : "Không",
        _ => Convert.ToString(value, CultureInfo.GetCultureInfo("vi-VN")) ?? "—"
    };
}
public sealed record SqlArgument(string Name, SqlDbType Type, object? Value, int Size = 0);
public sealed record ProcedureCall(string Name, IReadOnlyList<SqlArgument> Arguments);
public enum BookingAction { CheckIn, Deposit, CheckOut, Cancel, NoShow, CheckOutDemo     }
public sealed class BookingOperation
{
    [Required(ErrorMessage = "Chọn booking trước khi thực hiện.")]
    [RegularExpression(@"^[A-Za-z0-9_-]{1,10}$", ErrorMessage = "Mã booking tối đa 10 ký tự chữ, số, - hoặc _.")]
    public string BookingId { get; set; } = "";
    [Range(1, int.MaxValue, ErrorMessage = "Version phải là số nguyên dương.")]
    public int Version { get; set; } = 1;
    public BookingAction Action { get; set; }
    [Range(typeof(decimal), "0", "9999999999999999.99", ErrorMessage = "Số tiền nằm ngoài phạm vi DECIMAL(18,2).")]
    public decimal Amount { get; set; }
    public string? PaymentId { get; set; }
    public decimal NoShowFee { get; set; }
}
public sealed class NewBooking : IValidatableObject
{
    public string BookingId { get; set; } = "";
    public string CustomerId { get; set; } = "";
    [StringLength(200, ErrorMessage = "Tên khách hàng tối đa 200 ký tự.")]
    public string CustomerName { get; set; } = "";
    [StringLength(15, ErrorMessage = "Số điện thoại tối đa 15 ký tự.")]
    public string CustomerPhone { get; set; } = "";
    [StringLength(20, ErrorMessage = "CCCD tối đa 20 ký tự.")]
    public string CustomerIdentity { get; set; } = "";
    [StringLength(100, ErrorMessage = "Email tối đa 100 ký tự.")]
    public string CustomerEmail { get; set; } = "";
    [Required] public string StaffId { get; set; } = "";
    public string[] RoomIds { get; set; } = [];
    public DateTime ArrivalDate { get; set; } = DateTime.Today;
    public DateTime DepartureDate { get; set; } = DateTime.Today.AddDays(1);
    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (ArrivalDate.Date < DateTime.Today)
            yield return new ValidationResult("Ngày nhận không được trong quá khứ.", [nameof(ArrivalDate)]);
        if (string.IsNullOrWhiteSpace(CustomerId))
        {
            if (string.IsNullOrWhiteSpace(CustomerName))
                yield return new ValidationResult("Nhập tên khách hàng.", [nameof(CustomerName)]);
            if (string.IsNullOrWhiteSpace(CustomerPhone))
                yield return new ValidationResult("Nhập số điện thoại.", [nameof(CustomerPhone)]);
            if (string.IsNullOrWhiteSpace(CustomerIdentity))
                yield return new ValidationResult("Nhập CCCD.", [nameof(CustomerIdentity)]);
        }
        if (DepartureDate.Date <= ArrivalDate.Date || (DepartureDate.Date - ArrivalDate.Date).Days > 366)
            yield return new ValidationResult("Ngày trả phải sau ngày nhận, tối đa 366 đêm.", [nameof(DepartureDate)]);
        if (RoomIds is null || RoomIds.Length == 0)
            yield return new ValidationResult("Chọn ít nhất một phòng.", [nameof(RoomIds)]);
    }
}

public sealed class RoomTypeChange : IValidatableObject
{
    [Required(ErrorMessage = "Nhập mã loại phòng.")]
    [RegularExpression(@"^[A-Za-z0-9_-]{1,10}$", ErrorMessage = "Mã loại phòng tối đa 10 ký tự chữ, số, - hoặc _.")]
    public string RoomTypeId { get; set; } = "";
    [Required(ErrorMessage = "Nhập tên loại phòng.")]
    [StringLength(50, ErrorMessage = "Tên loại phòng tối đa 50 ký tự.")]
    public string RoomTypeName { get; set; } = "";
    [Range(typeof(decimal), "0", "9999999999999999.99", ErrorMessage = "Giá cơ bản không được âm.")]
    public decimal BasePrice { get; set; }
    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (string.IsNullOrWhiteSpace(RoomTypeId))
            yield return new ValidationResult("Nhập mã loại phòng.", [nameof(RoomTypeId)]);
        if (string.IsNullOrWhiteSpace(RoomTypeName))
            yield return new ValidationResult("Nhập tên loại phòng.", [nameof(RoomTypeName)]);
    }
}

public sealed class RoomTypePriceChange
{
    [Required(ErrorMessage = "Chọn loại phòng.")]
    public string RoomTypeId { get; set; } = "";
    [Range(typeof(decimal), "0", "9999999999999999.99", ErrorMessage = "Giá cơ bản không được âm.")]
    public decimal BasePrice { get; set; }
}

public sealed class CalendarRange : IValidatableObject
{
    public DateTime From { get; set; } = DateTime.Today;
    public DateTime To { get; set; } = DateTime.Today.AddDays(6);
    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        if (To.Date < From.Date)
            yield return new ValidationResult("Đến ngày phải bằng hoặc sau Từ ngày.", [nameof(To)]);
    }
}

// Services keep SQL inline; validation normalizes the values bound to SQL parameters.
public static class BookingValidation
{
    private static string Id(string? value, string label)
    {
        value = value?.Trim();
        if (value is null || !Regex.IsMatch(value, @"\A[A-Za-z0-9_-]{1,10}\z"))
            throw new ValidationException($"{label}: nhập mã 1–10 ký tự chữ, số, - hoặc _.");
        return value;
    }
    public static void Validate(NewBooking model)
    {
        model.BookingId = string.IsNullOrWhiteSpace(model.BookingId) ? "" : Id(model.BookingId, "Mã booking");
        if (!string.IsNullOrWhiteSpace(model.CustomerId))
            model.CustomerId = Id(model.CustomerId, "Khách hàng");
        model.StaffId = Id(model.StaffId, "Nhân viên");
        model.RoomIds = (model.RoomIds ?? []).Select(room => Id(room, "Phòng")).ToArray();
        if (model.RoomIds.Distinct(StringComparer.OrdinalIgnoreCase).Count() != model.RoomIds.Length)
            throw new ValidationException("Danh sách phòng không được trùng mã.");
        Validator.ValidateObject(model, new ValidationContext(model), validateAllProperties: true);
    }
    public static void Validate(BookingOperation model)
    {
        model.BookingId = Id(model.BookingId, "Mã booking");
        model.PaymentId = string.IsNullOrWhiteSpace(model.PaymentId) ? null : Id(model.PaymentId, "Mã giao dịch");
        if (model.Version < 1) throw new ValidationException("Version phải là số nguyên dương.");
        if (model.Amount < 0 || model.Amount > 9999999999999999.99m || decimal.Round(model.Amount, 2) != model.Amount)
            throw new ValidationException("Số tiền không âm, tối đa 2 chữ số thập phân.");
        switch (model.Action)
        {
            case BookingAction.NoShow:
                if (model.NoShowFee < 0 || model.NoShowFee > 9999999999999999.99m || decimal.Round(model.NoShowFee, 2) != model.NoShowFee)
                    throw new ValidationException("Phí no-show không âm, tối đa 2 chữ số thập phân.");
                goto case BookingAction.Cancel;
            case BookingAction.CheckIn: break;
            case BookingAction.Deposit:
                if (model.Amount <= 0)
                    throw new ValidationException("Đặt cọc cần số tiền dương.");
                break;
            case BookingAction.CheckOut:
            case BookingAction.CheckOutDemo:
                if (model.Amount < 0)
                    throw new ValidationException("Thanh toán không âm.");
                break;
            case BookingAction.Cancel:
                break;
            default: throw new ValidationException("Nghiệp vụ không hợp lệ.");
        }
    }
}

// Legacy mapping checks use the same validation as the inline SQL services.
public static class BookingCommands
{
    public static SqlArgument Code(string name, string? value) => new(name, SqlDbType.VarChar, value, 10);
    public static SqlArgument Money(string name, decimal value) => new(name, SqlDbType.Decimal, value);
    public static ProcedureCall Create(NewBooking model)
    {
        BookingValidation.Validate(model);
        return new("sp_DatPhong", [
            Code("MaDatPhong", model.BookingId),
            Code("MaKH", model.CustomerId),
            Code("MaNV", model.StaffId),
            new("NgayNhan", SqlDbType.Date, model.ArrivalDate.Date),
            new("NgayTra", SqlDbType.Date, model.DepartureDate.Date),
            new("DanhSachPhong", SqlDbType.Structured, model.RoomIds)]);
    }
    public static ProcedureCall Operation(BookingOperation model)
    {
        BookingValidation.Validate(model);
        var args = new List<SqlArgument> {
            Code("MaDatPhong", model.BookingId), new("Version", SqlDbType.Int, model.Version)
        };
        string? payment = model.PaymentId;
        string name;
        switch (model.Action)
        {
            case BookingAction.CheckIn: name = "sp_NhanPhong"; break;
            case BookingAction.Deposit:
                name = "sp_DatCoc"; args.Add(Code("MaGD", payment)); args.Add(Money("SoTien", model.Amount)); break;
            case BookingAction.CheckOut:
                name = "sp_TraPhong"; args.Add(Code("MaGD", payment)); args.Add(Money("SoTienThanhToan", model.Amount)); break;
            case BookingAction.Cancel:
                name = "sp_HuyBooking"; args.Add(Code("MaGDHoanTien", payment)); args.Add(Money("SoTienHoanTra", model.Amount)); break;
            case BookingAction.NoShow:
                name = "sp_NoShow_NhaPhong"; args.Add(Code("MaGDHoanTien", payment)); args.Add(Money("SoTienHoanTra", model.Amount)); args.Add(Money("PhiPhat", model.NoShowFee)); break;
            default: throw new ValidationException("Nghiệp vụ không hợp lệ.");
        }
        return new(name, args);
    }
}
public enum DemoCase { GroupBooking, CheckoutReport }
public enum DemoMode { Broken, Ordered, Timeout }
public sealed record DemoJob(string Actor, ProcedureCall Call);
public static class DemoCommands
{
    public static DemoJob[] For(DemoCase scenario, DemoMode mode)
    {
        if (!Enum.IsDefined(scenario) || !Enum.IsDefined(mode)) throw new ValidationException("Kịch bản không hợp lệ.");
        if (scenario == DemoCase.GroupBooking)
        {
            if (mode == DemoMode.Timeout) throw new ValidationException("Kịch bản đặt phòng không có bản timeout.");
            var name = mode == DemoMode.Broken ? "SP_DatPhong_Loi" : "SP_DatPhong_Fix";
            ProcedureCall Booking(string id, string customer, string staff, string first, string second) => new(name, [
                BookingCommands.Code("MaDatPhong",id), BookingCommands.Code("MaKH",customer), BookingCommands.Code("MaNV",staff),
                new("Ngay",SqlDbType.Date,new DateTime(2026,12,24)), BookingCommands.Code("MaPhong1",first), BookingCommands.Code("MaPhong2",second)]);
            return [new("Khách đặt online",Booking("DL1_A","KH01","WEB","V102","V101")),
                    new("Lễ tân đặt đoàn",Booking("DL1_B","KH02","NV01","V101","V102"))];
        }
        var report = mode switch { DemoMode.Broken => "SP_BaoCao_Loi", DemoMode.Timeout => "SP_BaoCao", _ => "sp_Web_BaoCao_Ordered" };
        return [new("Lễ tân thanh toán",new("SP_ThanhToan",[
            BookingCommands.Code("MaGD","GD_DL2"), BookingCommands.Code("MaDatPhong","DL2_CK"), BookingCommands.Money("SoTien",1200000m)])),
            new("Quản lý chốt ca",new(report,[]))];
    }
}
public sealed record DemoSession(string Actor, string Procedure, int SessionId, bool Success, int? ErrorCode,
    string Message, double Seconds, TableData Data);
public sealed record DemoOutcome(IReadOnlyList<DemoSession> Sessions, TableData Snapshot, string? SnapshotWarning);
