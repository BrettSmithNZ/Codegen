param($baseFolder = $(throw "You must specify your base folder"))
# Check if the user has powershell-yaml installed, if not then install
if (-not(Get-Module -ListAvailable -Name powershell-yaml)) {
    Install-Module -Name powershell-yaml
}

class ForeignKey {
    [string] $model
    [string] $property
    [string] $onDelete = $null
}

class ClassProperty {
    [string] $name
    [string] $type
    [bool] $primaryKey = $null
    [bool] $readOnly = $null
    [bool] $filterable = $null
    [bool] $nullable = $null
    [ForeignKey[]] $foreignKey = $null
}

class ClassItem {
    [string] $model
    [ClassProperty[]] $properties
}
class  TemplatePart {
    [string] $name
    [string] $fileName
}
class TemplateItem {
    [string] $name
    [bool] $consolidated = $null
    [TemplatePart[]] $parts = $null
    [string] $fileName
}

class BuildDefinition {
    [string] $resource
    [TemplateItem[]] $templates
    [ClassItem[]] $models
}

Function Set-CamelCase {
    param(
        [string] $source        
    )
    return "$($source.substring(0,1).ToUpper())$($source.Substring(1).ToLower())"
}
Function Set-Singular {
    param(
        [string] $source
    )
    return $source -replace ('ies$', 'y') -replace ('(s$)', '')
}
Function Get-PropertyType {
    param(
        [string] $type,
        [bool] $nullable = $null
    )
    if ($nullable) {
        return "$($type)?"
    }
    return $type;
}
Function Set-ContentVariables {
    param (
        [string[]] $classContent,
        [ClassItem] $class,
        [string] $indent = $null
    )

    $editableProperties = $class.properties.Where( { !([bool] $_.readOnly) })

    $editableMap = @($editableProperties | ForEach-Object { ("$($_.name) = source.$($_.name)") }) -join ",`n`t`t`t`t" 
    $propertymap = @($class.properties | ForEach-Object { ("$($_.name) = source.$($_.name)") }) -join ",`n`t`t`t`t" 

    $nameOfProperties = ($class.properties | ForEach-Object { ("nameof($($class.model).$($_.name))") }) -join ",`n`t`t`t`t`t`t"`
    
    $propertyGetterSetters = ($class.properties | ForEach-Object { ("public $(Get-PropertyType $_.type $_.nullable) $($_.name) { get; set; }") }) -join "`n`t`t"
    $editableGetterSetters = ($editableProperties | ForEach-Object { ("public $(Get-PropertyType $_.type $_.nullable) $($_.name) { get; set; }") }) -join "`n`t`t"
        
    $filterPropertyGetterSetters = @($class.properties.Where( { [bool]$_.filterable }) | ForEach-Object {
            "public $(Get-PropertyType $_.type $_.nullable) $($_.name) { get; set; }" 
        }) -join ",`n`t`t`t`t" 


    $filterProperties = @($class.properties.Where( { [bool]$_.filterable }) | ForEach-Object {
            ("IEnumerable<$(Get-PropertyType $_.type $_.nullable)> $($_.name) = null") 
        }) -join ",`n`t`t`t`t" 
        
    $keyProperties = @($class.properties.Where( { [bool]$_.primaryKey }) | ForEach-Object {
            ("$($(Get-PropertyType $_.type $_.nullable)) $($_.name)") 
        }) -join ",`n`t`t`t`t" 

    $keyPropertyConditions = @($class.properties.Where( { [bool]$_.primaryKey }) | ForEach-Object {
            "(nameof($($class.model).$($_.name)), new object[]{ $($_.name)})" 
        }) -join ",`n`t`t`t`t" 

    return  $classContent -join ("`r`n" + $indent) `
        -replace "%model%", $class.model `
        -replace "%modelFilters%", $filterProperties `
        -replace "%modelKeys%", $keyProperties `
        -replace "%propertymap%", $propertymap `
        -replace "%editableMap%", $editableMap `
        -replace "%nameOfProperties%", $nameOfProperties `
        -replace "%propertyGetterSetters%", $propertyGetterSetters `
        -replace "%filterPropertyGetterSetters%", $filterPropertyGetterSetters `
        -replace "%editableGetterSetters%", $editableGetterSetters `
        -replace "%keyPropertyConditions%", $keyPropertyConditions
}
Function Get-ClassContent {
    param (
        [ClassItem] $class,
        [string] $templateFile,
        [string] $indent = $null
    )
        
    [string[]]$templateContent = Get-Content -Path $templateFile

    return Set-ContentVariables $templateContent $class $indent
}
Function Save-ClassFile {
    param (
        [string] $namespace,
        [string] $typeName,
        [ClassItem] $class,
        [string] $outputFile,
        [string] $templateFile
    )

    $contentToSet = (Get-ClassContent $class $templateFile) `
        -replace "%namespace%", $namespace `
        -replace "%typeName%", $typeName
        
    $modelPath = $outputFile
    if (-not ( Test-Path -Path $modelPath)) {
        New-Item -Path $modelPath -Type File
    }
    Set-Content -Path $modelPath -Value $contentToSet 
}
Function Save-ContentFile {
    param (
        [string] $namespace,
        [string] $typeName,
        [string] $templatePath,
        [string] $contentFilePath,
        [string[]]$contentArray
    )
        
    [string[]]$templateContent = Get-Content -Path $templatePath

    $modelContent = $contentArray -join "`r`n`r`n`t`t"
            
    $content = $templateContent -join "`r`n" `
        -replace "%modelContent%", $modelContent `
        -replace "%namespace%", $namespace `
        -replace "%typeName%", $typeName

    if (-not(Test-Path -Path $contentFilePath)) {
        New-Item -Path $contentFilePath -Type File
    }
    Set-Content -Path $contentFilePath -Value $content
}

<# 
Bypass execution policy without changing defaults: 
ensures user recieves warning and is asked to confirm 
#>
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Import-Module powershell-yaml


Foreach ($project in (Get-ChildItem -Path $baseFolder )) {

    $projectPath = "$baseFolder\$project"
    $templateDirectory = "$projectPath\_generator\templates"
    $buildDefinitionPath = "$projectPath\_generator\project-build.yaml"
        
    if (Test-Path -Path $buildDefinitionPath) {
        
        if (Test-Path -Path "$projectPath\class1.cs") {
            Remove-Item "$projectPath\class1.cs"
        }

        [string[]] $fileContent = Get-Content -Path $buildDefinitionPath
        $content = $fileContent -join "`r`n"
        [BuildDefinition] $buildDefinition = ConvertFrom-Yaml $content -Ordered
        
        $folders = ($buildDefinition.templates | ForEach-Object { $_.name })

        Foreach ($folder in $folders) {
            if (Test-Path $projectPath\$folder) {
                Remove-Item $projectPath\$folder -Recurse 
            }
            mkdir $projectPath\$folder           
        }

        $typeName = Set-Singular $buildDefinition.resource

        $buildDefinition.templates | ForEach-Object {
            $template = $_

            $templateName = $template.name;

            $fileName = $template.fileName -replace "%resource%", (Set-Singular $buildDefinition.resource)

            if ($template.consolidated) {

                $templateFiles = Get-ChildItem -Path $templateDirectory -Filter "$($templateName).*"
                
                foreach ($templateFile in ($templateFiles -notlike '*.model.template')) {
                
                    $contentArray = @();

                    $buildDefinition.models | ForEach-Object {
                        $class = $_
    
                        $contentArray += Get-ClassContent $class `
                            "$templateDirectory\$($templateFile -replace '.template' , '.model.template')" `
                            "`t`t"
                    }
    

                    if ($templateFile -like '*.interface.*') {
                        $fileName = "I$($fileName)"
                    }
                    
               
                    Save-ContentFile $project $typeName `
                        "$templateDirectory\$($templateFile)" `
                        "$projectPath\$templateName\$fileName" `
                        $contentArray
                }
            }
            else {
                $buildDefinition.models | ForEach-Object {
                    $class = $_

                    if ($template.parts) {
                        $template.parts | ForEach-Object {
                            $part = $_
                            Save-ClassFile $project $typeName $class `
                                "$projectPath\$($templateName)\$($part.fileName -replace "%model%", $class.model)" `
                                "$templateDirectory\$($templateName).$($part.name).template"
                        }
                    }
                    else {
                        Save-ClassFile $project $typeName $class `
                            "$projectPath\$($templateName)\$($fileName -replace "%model%", $class.model)" `
                            "$templateDirectory\$($templateName).class.template"
                    }
                }
            }
        }
    }
}
