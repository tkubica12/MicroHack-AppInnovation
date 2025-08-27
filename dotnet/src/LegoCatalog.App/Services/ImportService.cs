using System.Text.Json;
using System.Text.Json.Serialization;
using LegoCatalog.App.Models;

namespace LegoCatalog.App.Services;

/// <summary>
/// Handles idempotent import of catalog JSON.
/// </summary>
public class ImportService
{
    private readonly IFigureRepository _figures;
    private readonly ICategoryRepository _categories;
    // Match JSON properties: productId, name, category, description, filename
    private record RawItem(
        [property: JsonPropertyName("productId")] string ProductId,
        string Name,
        string Category,
        string Description,
        [property: JsonPropertyName("filename")] string FileName
    );

    public ImportService(IFigureRepository figures, ICategoryRepository categories)
    {
        _figures = figures; _categories = categories;
    }

    public async Task<(int addedFigures, int totalParsed)> ImportAsync(Stream jsonStream, CancellationToken ct)
    {
        var items = await JsonSerializer.DeserializeAsync<List<RawItem>>(jsonStream, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        }, ct) ?? new();

        var toAdd = new List<LegoFigure>();
        foreach (var item in items)
        {
            if (string.IsNullOrWhiteSpace(item.ProductId) || string.IsNullOrWhiteSpace(item.Name) || string.IsNullOrWhiteSpace(item.Category)) continue;
            var idTrimmed = item.ProductId.Trim();
            if (idTrimmed.Length > 36) idTrimmed = idTrimmed[..36]; // safety: should not happen, prevent DB error
            var cat = await _categories.GetOrCreateAsync(item.Category.Trim(), ct);
            toAdd.Add(new LegoFigure
            {
                Id = idTrimmed,
                Name = item.Name.Trim(),
                CategoryId = cat.Id,
                Description = item.Description?.Trim() ?? string.Empty,
                ImageFile = item.FileName?.Trim() ?? string.Empty
            });
        }
        var added = await _figures.BulkInsertAsync(toAdd, ct);
        return (added, items.Count);
    }
}
