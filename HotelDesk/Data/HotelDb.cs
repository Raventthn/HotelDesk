using System.Data;
using HotelDesk.Models;
using Microsoft.Data.SqlClient;
namespace HotelDesk.Data;


public sealed class HotelDb(SqlConnectionFactory factory)
{
    public async Task<TableData> QueryAsync(string sql, SqlParameter[]? parameters = null, CancellationToken cancellation = default)
    {
        await using var connection = factory.Create();
        await connection.OpenAsync(cancellation);
        return await QueryOnAsync(connection, sql, parameters, cancellation);
    }
    public static async Task<TableData> QueryOnAsync(SqlConnection connection, string sql, SqlParameter[]? parameters, CancellationToken cancellation)
    {
        using var command = new SqlCommand(sql, connection)
        {
            CommandType = CommandType.Text,
            CommandTimeout = 45
        };
        if (parameters is not null) command.Parameters.AddRange(parameters);
        try { return await ReadAsync(command, cancellation); }
        catch
        {
            try
            {
                using var cleanup = new SqlCommand("IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;", connection) { CommandTimeout = 5 };
                await cleanup.ExecuteNonQueryAsync(CancellationToken.None);
            }
            catch { }
            throw;
        }
    }
    public static async Task<TableData> ReadAsync(SqlCommand command, CancellationToken cancellation)
    {
        await using var reader = await command.ExecuteReaderAsync(cancellation);
        var columns = new List<string>();
        var rows = new List<Dictionary<string, object?>>();
        do
        {
            if (reader.FieldCount == 0) continue;
            for (var i = 0; i < reader.FieldCount; i++)
                if (!columns.Contains(reader.GetName(i))) columns.Add(reader.GetName(i));
            while (await reader.ReadAsync(cancellation))
            {
                var row = new Dictionary<string, object?>();
                for (var i = 0; i < reader.FieldCount; i++)
                    row[reader.GetName(i)] = await reader.IsDBNullAsync(i, cancellation) ? null : reader.GetValue(i);
                rows.Add(row);
            }
        } while (await reader.NextResultAsync(cancellation)); 
        return new(columns, rows);
    }
}
