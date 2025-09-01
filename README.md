# MicroHack: Application Innovation
What is the next generation of modernization and why does it matter?

## MicroHack Context
We will work with simple Web applications built on .NET and SQL Server.

![](./images/catalog.png)

## MicroHack Objectives

## MicroHack Challenges
Focus on implementing at least first two challenges today as minimum out of four major challenges. 

Challenge 5 is designed for participants that have time to spare or as follow-up tasks after MicroHack and come in two optional flavors. Enterprise flavor is to enhance enterprise-grade security of the solution while Innovation flavor is to implement AI assistant capabilities into our application.

### Prerequisities and existing infrastructure
There is Azure subscription and Resource Group deployed for you. Inside you will find Virtual Machine with credentials ```azureuser``` and password ```Azure12345678``` accessible via Bastion host from Azure Portal. This VM contains application that use local SQL Server Express, .NET app and image files stored in a folder.

After VM starts use PowerShell script ```C:\start-app.ps1``` to run your application and access it at ```http://localhost:5000```.

You can also use this VM as your developer station. To quickly install tools such as Docker environment, Azure CLI, SQL Server Management Studio, git and Visual Studio Code execute PowerShell script ```C:\dev-tools-install.ps1```. You may also use your local computer or GitHub Codespaces for this MicroHack if you prefer.

Source code and important documentation for this application is stored in ```dotenet``` folder of this repository. In order to automate CI/CD later in a lab we suggest to clone this repo into your development environment.

### ch01: Migrate database, containerize application, deploy to Azure
[Challenge](/challenges/ch01/README.md) | [Solution]( /solutions/ch01/README.md)

### ch02: Test autoscaling under load
TBD

### ch03: Implement CI/CD pipeline to automatically deploy changes
TBD

### ch04: Monitor application performance with tracing
TBD

### ch05-enterprise: Implement security best practices
TBD

### ch05-innovation: Implement AI assistant
TBD