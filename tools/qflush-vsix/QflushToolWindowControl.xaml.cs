using System;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Web.WebView2.Wpf;

namespace Qflush.A11
{
    public partial class QflushToolWindowControl : UserControl
    {
        private WebView2 _webView;

        public QflushToolWindowControl()
        {
            InitializeComponent();
            InitializeWebView();
        }

        private async void InitializeWebView()
        {
            _webView = new WebView2
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Stretch
            };

            WebViewHost.Children.Add(_webView);

            try
            {
                await _webView.EnsureCoreWebView2Async();
                _webView.Source = new Uri("http://localhost:5173/");
            }
            catch (Exception ex)
            {
                MessageBox.Show(
                    "Impossible d'initialiser QFLUSH (WebView2).\n" + ex.Message,
                    "QFLUSH - A-11",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error
                );
            }
        }
    }
}
