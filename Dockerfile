# syntax=docker/dockerfile:1

FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY HotelDesk/HotelDesk.csproj HotelDesk/
RUN dotnet restore HotelDesk/HotelDesk.csproj

COPY HotelDesk/ HotelDesk/
RUN dotnet publish HotelDesk/HotelDesk.csproj \
    --configuration Release \
    --output /app/publish \
    --no-restore \
    /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

ENV ASPNETCORE_URLS=http://+:8080 \
    ASPNETCORE_ENVIRONMENT=Production

EXPOSE 8080
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "HotelDesk.dll"]
