using LegoCatalog.App.Models;

namespace LegoCatalog.App.Services;

/// <summary>
/// Application service providing catalog query operations.
/// </summary>
public class FigureCatalogService
{
    private readonly IFigureRepository _figures;
    private readonly ICategoryRepository _categories;
    public FigureCatalogService(IFigureRepository figures, ICategoryRepository categories)
    {
        _figures = figures; _categories = categories;
    }

    public Task<IReadOnlyList<LegoFigure>> ListAsync(string? category, string? search, CancellationToken ct) => _figures.ListAsync(category, search, ct);
    public Task<LegoFigure?> GetAsync(string id, CancellationToken ct) => _figures.GetAsync(id, ct);
    public Task<List<Category>> CategoriesAsync(CancellationToken ct) => _categories.ListAsync(ct);
}
