using LegoCatalog.App.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace LegoCatalog.App.Pages;

public class ImportModel : PageModel
{
    private readonly ImportService _importService;
    public string? Message { get; set; }

    [BindProperty]
    public IFormFile? CatalogFile { get; set; }

    public ImportModel(ImportService importService) => _importService = importService;

    public void OnGet() { }

    public async Task<IActionResult> OnPostAsync(CancellationToken ct)
    {
        if (CatalogFile is null || CatalogFile.Length == 0)
        {
            Message = "No file selected.";
            return Page();
        }
        await using var stream = CatalogFile.OpenReadStream();
        var (added, total) = await _importService.ImportAsync(stream, ct);
        Message = $"Parsed {total} items; added {added} new.";
        return Page();
    }
}
