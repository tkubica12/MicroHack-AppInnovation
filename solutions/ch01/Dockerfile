# Multi-stage build (SDK -> runtime) for Linux
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copy project file first for layer caching
COPY src/LegoCatalog.App/*.csproj ./LegoCatalog.App/
RUN dotnet restore ./LegoCatalog.App/LegoCatalog.App.csproj

# Copy remaining source
COPY src/LegoCatalog.App ./LegoCatalog.App

# Publish (implicit restore kept to avoid partial restore issues)
RUN dotnet publish ./LegoCatalog.App/LegoCatalog.App.csproj \
    -c Release \
    -o /out

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

# Non-root user
RUN useradd -u 64100 -m appuser \
    && mkdir -p /app /data/images /seed \
    && chown -R appuser:appuser /app /data /seed

# Copy published output
COPY --from=build /out ./

ENV ASPNETCORE_URLS=http://0.0.0.0:8080 \
    DOTNET_EnableDiagnostics=0 \
    # Placeholder paths (override / mount as needed)
    IMAGE_ROOT_PATH=/data/images \
    SEED_DATA_PATH=/seed/catalog.json

EXPOSE 8080

USER appuser

ENTRYPOINT ["dotnet", "LegoCatalog.App.dll"]

