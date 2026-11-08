using DiGi.Maintenance.Classes;
using System.Globalization;
using System.Reflection;
using System.Xml.Linq;

namespace DiGi.Maintenance
{
    public static partial class Modify
    {
        /// <summary>
        /// Writes the version information of the specified solution to the Directory.Build.props file.
        /// </summary>
        /// <param name="solution">The solution instance whose version is to be written.</param>
        /// <returns>True if the operation was successful; otherwise, false.</returns>
        public static bool Write(this Solution solution)
        {
            if (solution.Path is not string path || string.IsNullOrWhiteSpace(path) || !System.IO.File.Exists(path))
            {
                return false;
            }

            string? directory = System.IO.Path.GetDirectoryName(path);

            if (solution.Version is System.Version version)
            {
                string path_Properties = System.IO.Path.Combine(directory, "Directory.Build.props");
                if (System.IO.File.Exists(path_Properties))
                {
                    // Read file text (trim whitespace to handle BOM/leading whitespace)
                    string xmlText = System.IO.File.ReadAllText(path_Properties).Trim();

                    // Parse it as XML
                    if (XDocument.Parse(xmlText) is XDocument xDocument)
                    {
                        if (xDocument.Root?.Element("PropertyGroup") is XElement xElement)
                        {
                            xElement.Element("Major").Value = version.Major.ToString(CultureInfo.CurrentCulture);
                            xElement.Element("Minor").Value = version.Minor.ToString(CultureInfo.CurrentCulture);
                            xElement.Element("Build").Value = version.Build.ToString(CultureInfo.CurrentCulture);
                        }

                        xDocument.Save(path_Properties);
                    }
                }
            }

            return true;
        }

        /// <summary>
        /// Writes the specified maintenance configuration file to the default configuration path relative to the executing assembly.
        /// </summary>
        /// <param name="maintenanceConfigurationFile">The maintenance configuration file instance to write.</param>
        /// <returns>True if the operation was successful; otherwise, false.</returns>
        public static bool Write(this MaintenanceConfigurationFile maintenanceConfigurationFile)
        {
            if (maintenanceConfigurationFile is null)
            {
                return false;
            }

            if (System.IO.Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location) is not string directory)
            {
                return false;
            }

            string path = System.IO.Path.Combine(directory, Constants.FileName.ConfigurationFile);

            return maintenanceConfigurationFile.Write(path);
        }
    }
}