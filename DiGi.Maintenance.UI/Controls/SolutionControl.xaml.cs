using DiGi.Maintenance.Classes;
using System.Globalization;
using System.Windows.Controls;

namespace DiGi.Maintenance.UI.Controls
{
    /// <summary>
    /// Interaction logic for SolutionControl.xaml
    /// </summary>
    public partial class SolutionControl : UserControl
    {
        private Solution? solution;

        /// <summary>
        /// Initializes a new instance of the <see cref="SolutionControl"/> class.
        /// </summary>
        public SolutionControl()
        {
            InitializeComponent();
        }

        /// <summary>
        /// Gets or sets the <see cref="Solution"/> associated with this control.
        /// </summary>
        public Solution? Solution
        {
            get
            {
                if (solution is null)
                {
                    return null;
                }

                solution.Version = Version;

                return solution;
            }

            set
            {
                solution = value;

                TextBox_Name.Text = solution?.GetName();

                Version = solution?.Version;
            }
        }

        /// <summary>
        /// Gets or sets the <see cref="Version"/> of the current solution.
        /// </summary>
        public Version? Version
        {
            get
            {
                if (!Core.Query.TryConvert(TextBox_Version_Major.Text, out int major))
                {
                    major = -1;
                }

                if (!Core.Query.TryConvert(TextBox_Version_Minor.Text, out int minor))
                {
                    major = -1;
                }

                if (!Core.Query.TryConvert(TextBox_Version_Build.Text, out int build))
                {
                    major = -1;
                }

                return new Version(major, minor, build);
            }

            set
            {
                if (value != null)
                {
                    TextBox_Version_Major.Text = value.Major == -1 ? string.Empty : value.Major.ToString(CultureInfo.CurrentCulture);
                    TextBox_Version_Minor.Text = value.Minor == -1 ? string.Empty : value.Minor.ToString(CultureInfo.CurrentCulture);
                    TextBox_Version_Build.Text = value.Build == -1 ? string.Empty : value.Build.ToString(CultureInfo.CurrentCulture);
                }
                else
                {
                    TextBox_Version_Major.Text = string.Empty;
                    TextBox_Version_Minor.Text = string.Empty;
                    TextBox_Version_Build.Text = string.Empty;
                }
            }
        }
    }
}