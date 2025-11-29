using Microsoft.VisualStudio.Shell;
using System;
using System.Runtime.InteropServices;

namespace Qflush.A11
{
    [Guid("d1a9b8e3-8c9f-4f2b-9a3b-0a1b2c3d4e5f")]
    public class QflushToolWindow : ToolWindowPane
    {
        public QflushToolWindow() : base(null)
        {
            this.Caption = "QFLUSH (A-11)";
            this.Content = new QflushToolWindowControl();
        }
    }
}
