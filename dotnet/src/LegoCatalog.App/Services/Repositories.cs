using LegoCatalog.App.Data;
using LegoCatalog.App.Models;
using Microsoft.EntityFrameworkCore;

namespace LegoCatalog.App.Services;

public interface IFigureRepository
{
    Task<bool> IsEmptyAsync(CancellationToken ct);
    Task<int> BulkInsertAsync(IEnumerable<LegoFigure> figures, CancellationToken ct);
    Task<IReadOnlyList<LegoFigure>> ListAsync(string? category, string? search, CancellationToken ct);
    Task<LegoFigure?> GetAsync(string id, CancellationToken ct);
    Task<int> CountAsync(CancellationToken ct);
}

public interface ICategoryRepository
{
    Task<Category?> GetByNameAsync(string name, CancellationToken ct);
    Task<Category> GetOrCreateAsync(string name, CancellationToken ct);
    Task<Dictionary<string, int>> GetNameIdMapAsync(CancellationToken ct);
    Task<List<Category>> ListAsync(CancellationToken ct);
}

public class FigureRepository : IFigureRepository
{
    private readonly CatalogDbContext _db;
    public FigureRepository(CatalogDbContext db) => _db = db;

    public async Task<bool> IsEmptyAsync(CancellationToken ct) => !await _db.Figures.AnyAsync(ct);

    public Task<int> CountAsync(CancellationToken ct) => _db.Figures.CountAsync(ct);

    public async Task<int> BulkInsertAsync(IEnumerable<LegoFigure> figures, CancellationToken ct)
    {
        // Load existing IDs once to avoid N queries and for accurate duplicate detection
    // EF Core (current version) doesn't expose ToHashSetAsync, so materialize then convert
    var existingIds = (await _db.Figures.AsNoTracking().Select(f => f.Id).ToListAsync(ct)).ToHashSet();
        int added = 0;
        foreach (var f in figures)
        {
            if (existingIds.Contains(f.Id)) continue;
            f.CreatedUtc = DateTime.UtcNow;
            f.LastUpdatedUtc = f.CreatedUtc;
            _db.Figures.Add(f);
            existingIds.Add(f.Id);
            added++;
        }
        if (added > 0) await _db.SaveChangesAsync(ct);
        return added;
    }

    public async Task<IReadOnlyList<LegoFigure>> ListAsync(string? category, string? search, CancellationToken ct)
    {
        var q = _db.Figures.Include(f => f.Category).AsQueryable();
        if (!string.IsNullOrWhiteSpace(category)) q = q.Where(f => f.Category!.Slug == category || f.Category.Name == category);
        if (!string.IsNullOrWhiteSpace(search)) q = q.Where(f => f.Name.Contains(search));
        return await q.OrderBy(f => f.Id).ToListAsync(ct);
    }

    public Task<LegoFigure?> GetAsync(string id, CancellationToken ct) => _db.Figures.Include(f => f.Category).FirstOrDefaultAsync(f => f.Id == id, ct);
}

public class CategoryRepository : ICategoryRepository
{
    private readonly CatalogDbContext _db;
    public CategoryRepository(CatalogDbContext db) => _db = db;

    public Task<Category?> GetByNameAsync(string name, CancellationToken ct) => _db.Categories.FirstOrDefaultAsync(c => c.Name == name, ct);

    public async Task<Category> GetOrCreateAsync(string name, CancellationToken ct)
    {
        var existing = await GetByNameAsync(name, ct);
        if (existing != null) return existing;
        var slug = Slugify(name);
        var cat = new Category { Name = name, Slug = slug };
        _db.Categories.Add(cat);
        await _db.SaveChangesAsync(ct);
        return cat;
    }

    public async Task<Dictionary<string, int>> GetNameIdMapAsync(CancellationToken ct)
    {
        return await _db.Categories.AsNoTracking().ToDictionaryAsync(c => c.Name, c => c.Id, ct);
    }

    public Task<List<Category>> ListAsync(CancellationToken ct) => _db.Categories.OrderBy(c => c.Name).ToListAsync(ct);

    private static string Slugify(string value) => new string(value.ToLowerInvariant().Where(c => char.IsLetterOrDigit(c) || c == ' ').ToArray()).Replace(' ', '-');
}
