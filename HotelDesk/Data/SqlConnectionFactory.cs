using Microsoft.Data.SqlClient;
namespace HotelDesk.Data;

// Only configuration is retained. A SqlConnection is never scoped to a Blazor circuit or shared between users.
public sealed class SqlConnectionFactory(IConfiguration configuration)
{
    public bool IsConfigured => !string.IsNullOrWhiteSpace(configuration.GetConnectionString("Hotel"));
    public SqlConnection Create(bool demo = false)
    {
        var key = demo ? "HotelDemo" : "Hotel";
        var value = configuration.GetConnectionString(key);
        if (string.IsNullOrWhiteSpace(value))
            throw new InvalidOperationException($"Chưa cấu hình ConnectionStrings:{key}. Demo cần database riêng. Xem README.md để kết nối SQL Server.");
        var settings = new SqlConnectionStringBuilder(value) {
            ApplicationName = demo ? "HotelDesk.Blazor.Deadlock" : "HotelDesk.Blazor",
            ConnectTimeout = 5, MultipleActiveResultSets = false, Enlist = false
        };
        if (demo)
        {
            if (!string.Equals(settings.InitialCatalog, "QL_KhachSan_Demo", StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Demo phải kết nối database QL_KhachSan_Demo riêng.");
            var productValue = configuration.GetConnectionString("Hotel");
            if (!string.IsNullOrWhiteSpace(productValue) && string.Equals(new SqlConnectionStringBuilder(productValue).InitialCatalog, settings.InitialCatalog, StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("Database sản phẩm và demo phải khác nhau.");
            settings.Pooling = false;
        }
        return new SqlConnection(settings.ConnectionString);
    }
}
