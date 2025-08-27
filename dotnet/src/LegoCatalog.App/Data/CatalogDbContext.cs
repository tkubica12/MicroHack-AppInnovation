using LegoCatalog.App.Models;
using Microsoft.EntityFrameworkCore;

namespace LegoCatalog.App.Data;

/// <summary>
/// EF Core DbContext for the catalog.
/// </summary>
public class CatalogDbContext : DbContext
{
    public CatalogDbContext(DbContextOptions<CatalogDbContext> options) : base(options) {}

    public DbSet<Category> Categories => Set<Category>();
    public DbSet<LegoFigure> Figures => Set<LegoFigure>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<Category>(e =>
        {
            e.HasKey(c => c.Id);
            e.HasIndex(c => c.Name).IsUnique();
            e.HasIndex(c => c.Slug).IsUnique();
            e.Property(c => c.Name).HasMaxLength(64).IsRequired();
            e.Property(c => c.Slug).HasMaxLength(64).IsRequired();
        });

        modelBuilder.Entity<LegoFigure>(e =>
        {
            e.HasKey(f => f.Id);
            // GUIDs from seed file -> 36 chars (including hyphens). Use 36 to avoid truncation.
            e.Property(f => f.Id).HasMaxLength(36);
            e.Property(f => f.Name).HasMaxLength(80).IsRequired();
            e.Property(f => f.Description).IsRequired();
            e.Property(f => f.ImageFile).HasMaxLength(64).IsRequired();
            e.HasIndex(f => f.Name);
            e.HasOne(f => f.Category)
                .WithMany(c => c.Figures)
                .HasForeignKey(f => f.CategoryId)
                .OnDelete(DeleteBehavior.Cascade);
        });
    }
}
