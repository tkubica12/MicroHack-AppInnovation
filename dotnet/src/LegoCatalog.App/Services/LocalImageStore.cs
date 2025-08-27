namespace LegoCatalog.App.Services;

public interface IImageStore
{
    string GetImageUrl(string fileName);
}

/// <summary>
/// Local file-backed image store – constructs relative URLs served by the image endpoint.
/// </summary>
public class LocalImageStore : IImageStore
{
    public string GetImageUrl(string fileName) => $"/images/{fileName}";
}
